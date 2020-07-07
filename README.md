# GoogleCloudLogging

Event logging for client applications on [Apple platforms](#supported-platforms) with support for offline work and automatic upload to [Google Cloud (GCP)](https://cloud.google.com). The package depends on [SwiftLog](https://github.com/apple/swift-log) - an official logging API for Swift, so it can be easly integrated into the project and combined with other logging backends. Log events are stored locally in the [JSON Lines](http://jsonlines.org) file format and bulk uploaded to GCP using the [Cloud Logging API v2](https://cloud.google.com/logging/docs/reference/v2/rest) at time intervals, upon defined event or explicit request.

> And yes, it logs itself! (with recursion protection) 🤘

## Rationale
Google-recommended logging solution for client applications is the Analytics framework, which is now part of the Firebase SDK. Here is a comparison of their framework and this library in terms of logging:
Library | FirebaseAnalytics | GoogleCloudLogging
--- | --- | ---
Platform | Mobile only. _Even Catalyst is not currently supported._ | All modern Apple's OSs. _It is essential for development of universal SwiftUI apps._
Source code | Closed source. _All application and users data is available to Google._ | Open source. _A few hundred lines of pure Swift, no implicit data submission._
Dependences | Part of the Firebase SDK. _Brings a bunch of Objective-C/C++ code with runtime swizzling etc._ | Only relies on SwiftLog and Apple's embedded frameworks.
Distribution | CocoaPods/Carthage. _SwiftPM is currently cannot be supported due to closed source and dependencies._ | SwiftPM, _which is preferred as integrated with the Swift build system._
Backend | Google Analytics for Firebase. _Includes some predefined marketing tools._ | GCP Operations (formerly Stackdriver). _Flexible custom log views, metrics, notifications, export etc._
Integration | Registration of your app in Google is required. | Only need to generate an access key.
Logging | Proprietary logging functions and implicit usage tracking. | SwiftLog logging API. _Single line connection of logging backend._

## Getting Started
### Add Package Dependency
Open your application project in Xcode 11 or later, go to menu `File -> Swift Packages -> Add Package Dependency...` and paste the package repository URL `https://github.com/DnV1eX/GoogleCloudLogging.git`.

### Create Service Account
In your web browser, open the [Google Cloud Console](https://console.cloud.google.com) and create a new project. In `IAM & Admin -> Service Accounts` create a service account choosing `Logging -> Logs Writer` role. In the last step, create and download private key choosing `JSON` format. You need to include this file in your application bundle.

> Just drag the file into the Xcode project and tick the desired targets in the file inspector.

### Setup Logging
1. Import both `SwiftLog` and `GoogleCloudLogging` modules:
```swift
import Logging
import GoogleCloudLogging
```

2. Register the logging backend once after the app launch:
```swift
LoggingSystem.bootstrap(GoogleCloudLogHandler.init)
```
Alternatively, you can register several backends, for example, in order to send logs to both GCP and the Xcode console:
```swift
LoggingSystem.bootstrap { MultiplexLogHandler([GoogleCloudLogHandler(label: $0), StreamLogHandler.standardOutput(label: $0)]) }
```

3. Configure GoogleCloudLogHandler:
```swift
do {
    try GoogleCloudLogHandler.setup(serviceAccountCredentials: Bundle.main.url(forResource: /* GCP private key file name */, withExtension: "json")!, clientId: UIDevice.current.identifierForVendor)
} catch {
    // Log GoogleCloudLogHandler setup error
}
```
If UIKit is not available, you can generate random `clientId` using `UUID()` and store it between the app launches.

> You can customize GoogleCloudLogHandler's static variables which are all thread safe and documented in the [source code](Sources/GoogleCloudLogging/GoogleCloudLogHandler.swift).

> It is recommended to explicitly upload logs calling `GoogleCloudLogHandler.upload()` when hiding or exiting the app.

## How to Use
### Emit Logs
1. Import `SwiftLog` module into the desired file:
```swift
import Logging
```

2. Create `logger` which can be a type, instance, or global constant or variable:
```swift
static let logger = Logger(label: /* Logged class name */)
```
> You can customize the minimum emitted log level and set the logger metadata.

3. Emit log messages in a certain log level:
```swift
logger.info(/* Logged info message */)
logger.error(/* Logged error message */, metadata: [LogKey.error: "\(error)"])
```
> It is a good practice to define `typealias LogKey = GoogleCloudLogHandler.MetadataKey` and extend it with your custom keys rather than use string literals.

> `GoogleCloudLogHandler.globalMetadata` takes precedence over `Logger` metadata which in turn takes precedence over log message metadata in case of key overlapping.

### Analyze Logs
In your web browser, open the [GCP Operations Logging](https://console.cloud.google.com/logs) and select your project. You will see a list of logs for a given **time range** which can be filtered by **log name** _(logger label)_, **severity** _(log level)_, **text payload** _(message)_, **labels** _(metadata)_ etc. **Resource type** for logs produced by GoogleCloudLogHandler is always _Global_.

> You can switch to the new Logs Viewer Preview that introduces new features, such as advanced log queries and histograms.

> Click on _clientId_ label value of the desired log entry and pick "Show matching entries" in order to view logs from the same app instance only.

## Supported Platforms
* iOS 11+
* iPadOS 13+
* macOS 10.13+
* tvOS 11+
* watchOS 4+

## License
Copyright © 2020 DnV1eX. All rights reserved.
Licensed under the Apache License, Version 2.0.
