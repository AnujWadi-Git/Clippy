import Foundation

sensitiveChecks()
processingChecks()
storageChecks()
aiChecks()
intelligenceChecks()
commandModeChecks()
searchIntelligenceChecks()
if CommandLine.arguments.contains("--live-ai") { liveAIChecks() }

print("\n\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
