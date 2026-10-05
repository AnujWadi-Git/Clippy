import Foundation

if CommandLine.arguments.contains("--eval") { runRetrievalEval(); exit(0) }
sensitiveChecks()
processingChecks()
storageChecks()
ocrChecks()
aiChecks()
intelligenceChecks()
commandModeChecks()
searchIntelligenceChecks()
if CommandLine.arguments.contains("--live-ai") { liveAIChecks() }

print("\n\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
