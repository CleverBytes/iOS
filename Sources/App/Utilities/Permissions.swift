import CoreLocation
import CoreMotion
import Foundation
import Shared
import UIKit
import UserNotifications

public enum PermissionStatus {
    case notDetermined
    case denied
    case authorized
    case authorizedWhenInUse // CLAuthorizationStatus only
    case restricted // Used if UNAuthorizationStatus is .provisional
    case unknown

    var description: String {
        switch self {
        case .notDetermined:
            return "Not determined"
        case .restricted:
            return "Restricted"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .authorizedWhenInUse:
            return "Authorized when in use"
        case .unknown:
            return "Unknown"
        }
    }
}

extension CLAuthorizationStatus {
    var genericStatus: PermissionStatus {
        switch self {
        case .notDetermined:
            return PermissionStatus.notDetermined
        case .restricted:
            return PermissionStatus.restricted
        case .denied:
            return PermissionStatus.denied
        case .authorizedAlways:
            return PermissionStatus.authorized
        case .authorizedWhenInUse:
            return PermissionStatus.authorizedWhenInUse
        @unknown default:
            Current.Log.warning("Caught unknown CLAuthorizationStatus \(self), returning PermissionStatus.unknown")
            return PermissionStatus.unknown
        }
    }
}

extension CMAuthorizationStatus {
    var genericStatus: PermissionStatus {
        switch self {
        case .notDetermined:
            return PermissionStatus.notDetermined
        case .restricted:
            return PermissionStatus.restricted
        case .denied:
            return PermissionStatus.denied
        case .authorized:
            return PermissionStatus.authorized
        @unknown default:
            Current.Log.warning("Caught unknown CMAuthorizationStatus \(self), returning PermissionStatus.unknown")
            return PermissionStatus.unknown
        }
    }
}

extension UNAuthorizationStatus {
    var genericStatus: PermissionStatus {
        switch self {
        case .notDetermined:
            return PermissionStatus.notDetermined
        case .provisional:
            return PermissionStatus.restricted
        case .denied:
            return PermissionStatus.denied
        case .ephemeral:
            return PermissionStatus.authorized
        case .authorized:
            return PermissionStatus.authorized
        @unknown default:
            Current.Log.warning("Caught unknown UNAuthorizationStatus \(self), returning PermissionStatus.unknown")
            return PermissionStatus.unknown
        }
    }
}

extension FocusStatusWrapper.AuthorizationStatus {
    var genericStatus: PermissionStatus {
        switch self {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        }
    }
}

public enum PermissionType {
    case location
    case motion
    case notification
    case focus

    var title: String {
        switch self {
        case .location:
            return L10n.Onboarding.Permissions.Location.title
        case .motion:
            return L10n.Onboarding.Permissions.Motion.title
        case .notification:
            return L10n.Onboarding.Permissions.Notification.title
        case .focus:
            return L10n.Onboarding.Permissions.Focus.title
        }
    }

    var enableIcon: MaterialDesignIcons {
        switch self {
        case .location: return .mapMarkerOutlineIcon
        case .motion: return .runIcon
        case .notification: return .bellOutlineIcon
        case .focus: return .powerSleepIcon
        }
    }

    var enableDescription: String {
        switch self {
        case .location:
            return L10n.Onboarding.Permissions.Location.grantDescription
        case .motion:
            return L10n.Onboarding.Permissions.Motion.grantDescription
        case .notification:
            return L10n.Onboarding.Permissions.Notification.grantDescription
        case .focus:
            return L10n.Onboarding.Permissions.Focus.grantDescription
        }
    }

    struct BulletPoint {
        var id = UUID().uuidString
        let icon: MaterialDesignIcons
        let text: String
    }

    var enableBulletPoints: [BulletPoint] {
        switch self {
        case .location:
            return [
                BulletPoint(icon: .homeAutomationIcon, text: L10n.Onboarding.Permissions.Location.Bullet.automations),
                BulletPoint(icon: .mapOutlineIcon, text: L10n.Onboarding.Permissions.Location.Bullet.history),
                BulletPoint(icon: .wifiIcon, text: L10n.Onboarding.Permissions.Location.Bullet.wifi),
            ]
        case .motion:
            return [
                BulletPoint(icon: .walkIcon, text: L10n.Onboarding.Permissions.Motion.Bullet.steps),
                BulletPoint(icon: .mapMarkerDistanceIcon, text: L10n.Onboarding.Permissions.Motion.Bullet.distance),
                BulletPoint(icon: .bikeIcon, text: L10n.Onboarding.Permissions.Motion.Bullet.activity),
            ]
        case .notification:
            return [
                BulletPoint(icon: .alertDecagramIcon, text: L10n.Onboarding.Permissions.Notification.Bullet.alert),
                BulletPoint(icon: .textIcon, text: L10n.Onboarding.Permissions.Notification.Bullet.commands),
                BulletPoint(icon: .bellBadgeOutlineIcon, text: L10n.Onboarding.Permissions.Notification.Bullet.badge),
            ]
        case .focus:
            return [
                BulletPoint(icon: .homeAutomationIcon, text: L10n.Onboarding.Permissions.Focus.Bullet.automations),
                BulletPoint(icon: .cancelIcon, text: L10n.Onboarding.Permissions.Focus.Bullet.instant),
            ]
        }
    }

    var status: PermissionStatus {
        switch self {
        case .location:
            let locationManager = CLLocationManager()
            return locationManager.authorizationStatus.genericStatus
        case .motion:
            return CMMotionActivityManager.authorizationStatus().genericStatus
        case .notification:
            guard let authorizationStatus = fetchNotificationsAuthorizationStatus() else { return .denied }
            return authorizationStatus.genericStatus
        case .focus:
            return Current.focusStatus.authorizationStatus().genericStatus
        }
    }

    var isAuthorized: Bool {
        switch status {
        case .authorized, .authorizedWhenInUse:
            return true
        case .denied, .notDetermined, .restricted, .unknown:
            return false
        }
    }

    private func fetchNotificationsAuthorizationStatus() -> UNAuthorizationStatus? {
        if self != .notification { return nil }
        // Fix for UNNotificationCenter & @IBDesignable - https://stackoverflow.com/a/55803896/486182
        if ProcessInfo().processName.hasPrefix("IBDesignablesAgent") { return .notDetermined }
        var notificationSettings: UNNotificationSettings?
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            UNUserNotificationCenter.current().getNotificationSettings { setttings in
                notificationSettings = setttings
                semaphore.signal()
            }
        }

        semaphore.wait()
        return notificationSettings?.authorizationStatus
    }

    func request(_ completionHandler: @escaping (Bool, PermissionStatus) -> Void) {
        if status == .denied {
            let destination: UIApplication.OpenSettingsDestination

            switch self {
            case .location: destination = .location
            case .motion: destination = .motion
            case .notification: destination = .notification
            case .focus: destination = .focus
            }

            UIApplication.shared.openSettings(destination: destination, completionHandler: nil)
            completionHandler(false, .denied)
            return
        }

        switch self {
        case .location:
            if PermissionsLocationDelegate.shared == nil {
                PermissionsLocationDelegate.shared = PermissionsLocationDelegate()
            }

            PermissionsLocationDelegate.shared!.requestPermission { status in
                DispatchQueue.main.async {
                    completionHandler(status == .authorized || status == .authorizedWhenInUse, status)
                    PermissionsLocationDelegate.shared = nil
                }
            }
        case .motion:
            let manager = CMMotionActivityManager()
            let now = Date()

            manager.queryActivityStarting(from: now, to: now, to: .main, withHandler: { (_, error: Error?) in
                if let error = error as NSError?,
                   error.domain == CMErrorDomain,
                   error.code == CMErrorMotionActivityNotAuthorized.rawValue {
                    completionHandler(false, .denied)
                    return
                }
                completionHandler(true, .authorized)
            })
        case .notification:
            UNUserNotificationCenter.current().requestAuthorization(options: .defaultOptions) { granted, error in
                if let error {
                    Current.Log.error("Error when requesting notifications permissions: \(error)")
                }
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                    let status: PermissionStatus = granted ? .authorized : .denied
                    completionHandler(granted, status)
                }
            }

            if Current.isCatalyst {
                // we likely will not get a completion until the user responds to the notification
                // but we don't wanna delay onboarding for this
                completionHandler(status == .authorized, status)
            }
        case .focus:
            Current.focusStatus.requestAuthorization().done { status in
                completionHandler(status == .authorized, status.genericStatus)
            }
        }
    }
}

public extension UNAuthorizationOptions {
    static var defaultOptions: UNAuthorizationOptions {
        var opts: UNAuthorizationOptions = [.alert, .badge, .sound, .providesAppNotificationSettings]

        if !Current.isCatalyst {
            // we don't have provisioning for critical alerts in catalyst yet, and asking for permission errors
            opts.insert(.criticalAlert)
        }

        return opts
    }
}

private class PermissionsLocationDelegate: NSObject, CLLocationManagerDelegate {
    static var shared: PermissionsLocationDelegate?

    lazy var locationManager: CLLocationManager = .init()

    typealias LocationPermissionCompletionBlock = (PermissionStatus) -> Void
    var completionHandler: LocationPermissionCompletionBlock?

    override init() {
        super.init()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .notDetermined {
            return
        }

        if manager.authorizationStatus == .authorizedWhenInUse {
            locationManager.requestAlwaysAuthorization()
        }

        completionHandler?(manager.authorizationStatus.genericStatus)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        if status == .notDetermined {
            return
        }

        completionHandler?(status.genericStatus)
    }

    func requestPermission(_ completionHandler: @escaping LocationPermissionCompletionBlock) {
        self.completionHandler = completionHandler

        let status = locationManager.authorizationStatus

        switch status {
        case .notDetermined:
            locationManager.delegate = self
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            locationManager.delegate = self
            locationManager.requestAlwaysAuthorization()
        default:
            completionHandler(status.genericStatus)
        }
    }

    var isAuthorized: Bool {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            return true
        case .denied, .notDetermined, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    deinit {
        locationManager.delegate = nil
    }
}
