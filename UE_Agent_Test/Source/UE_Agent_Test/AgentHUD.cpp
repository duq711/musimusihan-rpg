#include "AgentHUD.h"
#include "AgentCharacter.h"
#include "AgentDoor.h"
#include "Engine/Canvas.h"
#include "Engine/Engine.h"
#include "GameFramework/PlayerController.h"
void AAgentHUD::DrawHUD()
{
    Super::DrawHUD();
    if (!Canvas) return;
    float X=Canvas->ClipX*.5f, Y=Canvas->ClipY*.5f;
    DrawLine(X-6,Y,X+6,Y,FLinearColor::White,1.5f);
    DrawLine(X,Y-6,X,Y+6,FLinearColor::White,1.5f);
    DrawRect(FLinearColor(0,0,0,.65f),18,18,430,66);
    DrawText(TEXT("UE AGENT TEST | 1인칭 문 시험"),FLinearColor::White,30,28,GEngine->GetMediumFont(),1.15f);
    DrawText(TEXT("W A S D: 이동   마우스: 둘러보기"),FLinearColor(.8f,.85f,.9f),30,57,GEngine->GetMediumFont(),1.f);
    if (auto* P=Cast<AAgentCharacter>(GetOwningPawn()))
        if (auto* D=P->GetUsableDoor())
        {
            const FString Message=D->IsTargetOpen()?TEXT("E: 문 닫기"):TEXT("E: 문 열기");
            DrawRect(FLinearColor(0,0,0,.78f),X-140,Y+40,280,48);
            float W,H; GetTextSize(Message,W,H,GEngine->GetMediumFont(),1.6f);
            DrawText(Message,FLinearColor(1,.9f,.5f),X-W*.5f,Y+50,GEngine->GetMediumFont(),1.6f);
        }
}
