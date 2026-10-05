import Foundation

sensitiveChecks()
processingChecks()

print("\n\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
