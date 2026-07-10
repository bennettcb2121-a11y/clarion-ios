import Foundation
import HealthKit

/// Persona-scoped HealthKit read sets — the port of the web repo's permissionScopes idea.
/// Apple reviewers favor apps that request only what they visibly use, and every requested
/// type must appear in the app's UI (the Today card shows the persona's own metrics).
enum PersonaScopes {
    /// Types every persona reads: the recovery/sleep core.
    private static var core: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRate)!, // avg/max HR per workout
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
            HKObjectType.quantityType(forIdentifier: .stepCount)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .basalEnergyBurned)!,
            HKObjectType.quantityType(forIdentifier: .oxygenSaturation)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
        ]
        types.insert(HKObjectType.workoutType())
        return types
    }

    /// Read set for a persona. NOTE: cycle types are deliberately out of v1 (extra App Review
    /// scrutiny category — see the plan); wrist temperature is the menopause flagship.
    static func readTypes(for persona: Persona) -> Set<HKObjectType> {
        var types = core
        switch persona {
        case .endurance:
            types.insert(HKObjectType.quantityType(forIdentifier: .vo2Max)!)
            types.insert(HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!)
        case .strength:
            break
        case .menopause:
            if let wrist = HKObjectType.quantityType(forIdentifier: .appleSleepingWristTemperature) {
                types.insert(wrist)
            }
        case .general:
            break
        }
        return types
    }

    /// One-line, human explanation shown on the permission primer screen BEFORE the system
    /// sheet — priming raises grant rates and shows reviewers deliberate scoping.
    static func primerCopy(for persona: Persona) -> String {
        switch persona {
        case .endurance:
            return "As a runner, Clarion reads your workouts, heart rate, HRV, VO\u{2082}max, sleep, and activity — nothing else."
        case .strength:
            return "For strength training, Clarion reads your workouts, heart rate, HRV, sleep, and activity — nothing else."
        case .menopause:
            return "Clarion reads your overnight wrist temperature, sleep, HRV, and activity — the signals that shift through the menopause transition. Nothing else."
        case .general:
            return "Clarion reads your sleep, heart rate, HRV, and daily activity — nothing else."
        }
    }
}
