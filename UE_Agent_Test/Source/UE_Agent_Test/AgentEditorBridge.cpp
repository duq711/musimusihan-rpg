#include "AgentEditorBridge.h"

#if WITH_EDITOR
#include "CoreMinimal.h"
#include "Containers/Ticker.h"
#include "Editor.h"
#include "Editor/EditorEngine.h"
#include "Engine/World.h"
#include "HAL/PlatformMisc.h"
#include "HAL/PlatformTime.h"
#include "Misc/CommandLine.h"
#include "Misc/CoreDelegates.h"
#include "Misc/Parse.h"
#include "PlayInEditorDataTypes.h"
#include "Settings/LevelEditorPlaySettings.h"
#include "UObject/Package.h"
#include "UObject/UObjectGlobals.h"

namespace
{
FDelegateHandle AgentEditorInitHandle;
FDelegateHandle AgentPIEStartedHandle;
FDelegateHandle AgentPIECancelledHandle;
bool bAgentEditorBridgeRegistered = false;
bool bAgentEditorFinishQueued = false;
bool bAgentPIEEndRequested = false;
bool bAgentPIEEndObserved = false;
uint8 AgentEditorExitCode = 0;
uint64 AgentPIEEndFrame = 0;
double AgentPIEEndDeadline = 0.0;

bool TickAgentEditorFinish(float)
{
    // This callback is owned by the core ticker, not by a soon-to-be-destroyed PIE actor.
    if (!bAgentPIEEndRequested)
    {
        bAgentPIEEndRequested = true;
        if (GEditor && (GEditor->PlayWorld || GEditor->IsPlaySessionInProgress()))
        {
            UE_LOG(LogTemp, Display, TEXT("AGENT_PIE_END_REQUEST: normal editor play-session teardown"));
            GEditor->RequestEndPlayMap();
        }
        return true;
    }

    const bool bPIEStillActive = GEditor &&
        (GEditor->PlayWorld || GEditor->IsPlaySessionInProgress() || GEditor->ShouldEndPlayMap());
    if (bPIEStillActive)
    {
        if (FPlatformTime::Seconds() >= AgentPIEEndDeadline)
        {
            UE_LOG(LogTemp, Error, TEXT("AGENT_PIE_END_FAILED: normal editor teardown did not complete within 30 seconds"));
            // Report a failing run, never a clean shutdown, if the editor cannot end PIE.
            FPlatformMisc::RequestExitWithStatus(false, 1, TEXT("AgentPIEEndTimeout"));
            return false;
        }
        return true;
    }

    if (!bAgentPIEEndObserved)
    {
        bAgentPIEEndObserved = true;
        AgentPIEEndFrame = GFrameCounter;
        UE_LOG(LogTemp, Display, TEXT("AGENT_PIE_ENDED: play world and session cleared"));
        return true;
    }
    if (GFrameCounter <= AgentPIEEndFrame)
        return true;

    // Give editor/Slate cleanup a full outer frame after PIE has ended before shutting down.
    UE_LOG(LogTemp, Display, TEXT("AGENT_EDITOR_CLEAN_EXIT_REQUEST: status=%d after_pie_cleanup=1"),
        static_cast<int32>(AgentEditorExitCode));
    FPlatformMisc::RequestExitWithStatus(false, AgentEditorExitCode, TEXT("AgentEditorTestComplete"));
    return false;
}

void RemoveAgentPIEObservers()
{
    FEditorDelegates::PostPIEStarted.Remove(AgentPIEStartedHandle);
    FEditorDelegates::CancelPIE.Remove(AgentPIECancelledHandle);
    AgentPIEStartedHandle.Reset();
    AgentPIECancelledHandle.Reset();
}

bool RequestAgentPlaySession(float)
{
    if (!GEditor || !GIsEditor || IsRunningCommandlet())
    {
        UE_LOG(LogTemp, Error, TEXT("AGENT_PIE_START_FAILED: editor unavailable after engine initialization"));
        return false;
    }

    UWorld* EditorWorld = GEditor->GetEditorWorldContext().World();
    const FString MapPackage = EditorWorld ? EditorWorld->GetOutermost()->GetName() : TEXT("<none>");
    if (!EditorWorld || EditorWorld->WorldType != EWorldType::Editor || MapPackage != TEXT("/Game/Maps/TestRoom"))
    {
        UE_LOG(LogTemp, Error, TEXT("AGENT_PIE_START_FAILED: saved startup map was not loaded; map=%s world_type=%d"),
            *MapPackage, EditorWorld ? static_cast<int32>(EditorWorld->WorldType) : -1);
        return false;
    }
    if (GEditor->PlayWorld || GEditor->GetPlaySessionRequest().IsSet())
    {
        UE_LOG(LogTemp, Error, TEXT("AGENT_PIE_START_FAILED: a play session already exists or is queued"));
        return false;
    }

    // This duplicate belongs only to this request. Never save or change the user's play settings.
    ULevelEditorPlaySettings* Settings = DuplicateObject<ULevelEditorPlaySettings>(
        GetDefault<ULevelEditorPlaySettings>(), GetTransientPackage());
    Settings->SetPlayNetMode(PIE_Standalone);
    Settings->SetRunUnderOneProcess(true);
    Settings->SetPlayNumberOfClients(1);
    Settings->bLaunchSeparateServer = false;
    Settings->EnableGameSound = false;
    Settings->EnablePIEEnterAndExitSounds = false;
    Settings->bShouldMinimizeEditorOnNonVRPIE = false;
    Settings->PIEAlwaysOnTop = false;
    Settings->NewWindowWidth = 960;
    Settings->NewWindowHeight = 540;
    FParse::Value(FCommandLine::Get(), TEXT("ResX="), Settings->NewWindowWidth);
    FParse::Value(FCommandLine::Get(), TEXT("ResY="), Settings->NewWindowHeight);
    Settings->NewWindowWidth = FMath::Max(Settings->NewWindowWidth, 320);
    Settings->NewWindowHeight = FMath::Max(Settings->NewWindowHeight, 240);
    // Automated controller input does not need to capture the user's physical mouse.
    Settings->GameGetsMouseControl = false;

    AgentPIEStartedHandle = FEditorDelegates::PostPIEStarted.AddLambda([](bool bIsSimulating)
    {
        UWorld* PlayWorld = GEditor ? GEditor->PlayWorld : nullptr;
        const bool bActualPIE = !bIsSimulating && PlayWorld && PlayWorld->WorldType == EWorldType::PIE;
        if (bActualPIE)
        {
            UE_LOG(LogTemp, Display, TEXT("AGENT_PIE_STARTED: world_type=PIE map=%s begun_play=%d"),
                *PlayWorld->GetOutermost()->GetName(), PlayWorld->HasBegunPlay() ? 1 : 0);
        }
        else
        {
            UE_LOG(LogTemp, Error, TEXT("AGENT_PIE_START_FAILED: post-start event had no actual PIE world; simulation=%d world_type=%d"),
                bIsSimulating ? 1 : 0, PlayWorld ? static_cast<int32>(PlayWorld->WorldType) : -1);
        }
        RemoveAgentPIEObservers();
    });
    AgentPIECancelledHandle = FEditorDelegates::CancelPIE.AddLambda([]()
    {
        UE_LOG(LogTemp, Error, TEXT("AGENT_PIE_START_FAILED: editor cancelled the play request"));
        RemoveAgentPIEObservers();
    });

    FRequestPlaySessionParams Request;
    Request.SessionDestination = EPlaySessionDestinationType::InProcess;
    Request.WorldType = EPlaySessionWorldType::PlayInEditor;
    Request.SessionPreviewTypeOverride = EPlaySessionPreviewType::NoPreview;
    Request.EditorPlaySettings = Settings;
    Request.GlobalMapOverride = TEXT("/Game/Maps/TestRoom");
    Request.bAllowOnlineSubsystem = false;
    // No destination viewport means a new PIE viewport in this editor process.
    // -RenderOffscreen uses a generic non-OS window for that viewport on this Mac build.
    UE_LOG(LogTemp, Display, TEXT("AGENT_PIE_REQUEST: saved_map=%s in_process=1 simulation=0 offscreen=%d"),
        *MapPackage, FParse::Param(FCommandLine::Get(), TEXT("RenderOffscreen")) ? 1 : 0);
    GEditor->RequestPlaySession(Request);
    return false;
}
}
#endif

void StartAgentEditorBridge()
{
#if WITH_EDITOR
    if (bAgentEditorBridgeRegistered || !FParse::Param(FCommandLine::Get(), TEXT("AgentPIE")))
        return;
    bAgentEditorBridgeRegistered = true;
    if (!GIsEditor || IsRunningCommandlet() || FParse::Param(FCommandLine::Get(), TEXT("game")))
    {
        UE_LOG(LogTemp, Error, TEXT("AGENT_PIE_START_FAILED: -AgentPIE requires a normal editor process, not -game or a commandlet"));
        return;
    }

    AgentEditorInitHandle = FCoreDelegates::OnFEngineLoopInitComplete.AddLambda([]()
    {
        FCoreDelegates::OnFEngineLoopInitComplete.Remove(AgentEditorInitHandle);
        AgentEditorInitHandle.Reset();
        // Let the initialized editor finish its first tick before queuing the ordinary PIE request.
        FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateStatic(&RequestAgentPlaySession), 0.5f);
    });
    UE_LOG(LogTemp, Display, TEXT("AGENT_PIE_ARMED: waiting for editor initialization"));
#endif
}

bool FinishAgentEditorTest(int32 ExitCode)
{
#if WITH_EDITOR
    if (bAgentEditorFinishQueued)
        return true;
    if (!GIsEditor || IsRunningCommandlet() || !GEditor || !GEditor->PlayWorld ||
        GEditor->PlayWorld->WorldType != EWorldType::PIE)
        return false;

    bAgentEditorFinishQueued = true;
    AgentEditorExitCode = static_cast<uint8>(FMath::Clamp(ExitCode, 0, 255));
    AgentPIEEndDeadline = FPlatformTime::Seconds() + 30.0;
    // Do not tear down the play world while its test actor's Tick is still on the stack.
    FTSTicker::GetCoreTicker().AddTicker(FTickerDelegate::CreateStatic(&TickAgentEditorFinish), 0.01f);
    return true;
#else
    return false;
#endif
}
