import Foundation

if CommandLine.arguments.contains("--perf") { perfChecks(); exit(0) }
if CommandLine.arguments.contains("--eval") { runRetrievalEval(); exit(0) }
sensitiveChecks()
processingChecks()
storageChecks()
ocrChecks()
richTextChecks()
aiChecks()
intelligenceChecks()
commandModeChecks()
archiveChecks()
searchIntelligenceChecks()
if CommandLine.arguments.contains("--live-ai") { liveAIChecks() }

print("\n\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
