#pragma once

#include "CoreTypes.h"

// Opt-in editor automation; ordinary project launches do not start PIE.
void StartAgentEditorBridge();

// Returns true when this editor bridge has taken ownership of ending PIE and exiting.
// False lets a non-PIE caller use its normal process-exit path.
bool FinishAgentEditorTest(int32 ExitCode);
