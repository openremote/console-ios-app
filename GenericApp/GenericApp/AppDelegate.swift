/*
 * Copyright 2025, OpenRemote Inc.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import UIKit
import Firebase
import CoreLocation
import IQKeyboardManagerSwift
import ORLib

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate, URLSessionDelegate {

    var window: UIWindow?
    let gcmMessageIDKey = "gcm.message_id"

    var geofenceProvider: GeofenceProvider?
    var fcmToken: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UIBarButtonItem.appearance().setTitleTextAttributes([NSAttributedString.Key.foregroundColor: UIColor(named: "or_green") as Any], for: .normal)
        UINavigationBar.appearance().titleTextAttributes = [NSAttributedString.Key.foregroundColor: UIColor(named: "or_green") as Any]
        UIBarButtonItem.appearance().tintColor = UIColor(named: "or_green")

        IQKeyboardManager.shared.isEnabled = true

        UNUserNotificationCenter.current().delegate = self
        // Configure Firebase on every launch, also when started in the background,
        // so the APNs token can be handed over and the FCM token is delivered
        FirebaseApp.configure()
        Messaging.messaging().delegate = self

        // if the app was launched because of geofencing

        // Redirects NSLog calls to file
        if let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileName = "\(Date()).log"
            let logFilePath = documentsDirectory.appendingPathComponent(fileName).path
            if let cPath = logFilePath.cString(using: .utf8) {
                freopen(cPath, "a+", stderr)
            }
        }

        if launchOptions?[UIApplication.LaunchOptionsKey.location] != nil {
            NSLog("%@", "App started from location update")
            // create new GeofenceProvider which creates a CLLocationManager that will receive the location update
            geofenceProvider = GeofenceProvider()
            if CLLocationManager.authorizationStatus() == .authorizedAlways {
                geofenceProvider?.startMonitoringSignificantLocationChanges()
            }
        } else if let remoteNotifcation = launchOptions?[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any] {
            NSLog("%@", "App started from remote notification")
            if let action = remoteNotifcation[DefaultsKey.actionKey] as? String {
                if action == Actions.geofenceRefresh {
                    geofenceProvider = GeofenceProvider()
                    geofenceProvider?.refreshGeofences()
                    if CLLocationManager.authorizationStatus() == .authorizedAlways {
                        geofenceProvider?.startMonitoringSignificantLocationChanges()
                    }
                }
            }
        }
        return true
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        if shortcutItem.type == "settings" {
            let userDefaults = UserDefaults(suiteName: DefaultsKey.groupEntitlement)
            userDefaults?.removeObject(forKey: DefaultsKey.realmKey)
            (self.window?.rootViewController as? SplashViewController)?.displaySettings = true
            self.window?.rootViewController?.dismiss(animated: false)
        }
    }

    func applicationWillResignActive(_ application: UIApplication) {
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
    }

    func applicationWillTerminate(_ application: UIApplication) {
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let action = userInfo[DefaultsKey.actionKey] as? String {
            if action == Actions.geofenceRefresh {
                if let controllerGeofenceProvider = (self.window?.topController as? ORViewcontroller)?.geofenceProvider {

                    controllerGeofenceProvider.refreshGeofences()
                } else if let delegateGeofenceProvider = geofenceProvider {
                    delegateGeofenceProvider.refreshGeofences()
                } else {
                    geofenceProvider = GeofenceProvider()
                    geofenceProvider!.refreshGeofences()
                }
            } else if action == Actions.store {
                if let data = userInfo[DefaultsKey.dataKey] as? [String: String] {
                    if let key = data["key"] {
                        if let storageProvider = (self.window?.topController as? ORViewcontroller)?.storageProvider {
                            storageProvider.store(key: key, data: data["value"])
                        } else {
                            let storageProvider = StorageProvider()
                            storageProvider.store(key: key, data: data["value"])
                        }
                    }
                }
            }
        }

        if let notificationIdString = userInfo[ActionType.notificationId] as? String, let notificationId = Int64(notificationIdString) {
            if let defaults = UserDefaults(suiteName: DefaultsKey.groupEntitlement), let consoleId = defaults.string(forKey: GeofenceProvider.consoleIdKey) {
                ORNotificationResource.sharedInstance.notificationDelivered(notificationId: notificationId, targetId: consoleId)
            }
        }
        completionHandler(UIBackgroundFetchResult.newData)
    }

    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler(ORNotificationHandler.shared.willPresent(notification))
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        ORNotificationHandler.shared.didReceive(response)
        completionHandler()
    }
}

extension AppDelegate: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        ORNotificationHandler.shared.didReceiveRegistrationToken(fcmToken)
    }
}
