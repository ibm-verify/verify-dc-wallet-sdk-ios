// swift-tools-version: 6.3.3

import PackageDescription

let package = Package(
	name: "IBM Verify DC",
	platforms: [.macOS(.v15), .iOS(.v17), .watchOS(.v10)],
	products: [
		.library(
			name: "EudiWalletKit",
			targets: ["EudiWalletKit"])
	],
	dependencies: [
		.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-iso18013-data-transfer.git", exact: "0.32.2"),
		.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-wallet-storage.git", exact: "0.27.1"),
		.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-sdjwt-swift.git", exact: "0.15.1"),
		.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-openid4vp-swift.git", exact: "0.44.3"),
		.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-openid4vci-swift.git", exact: "0.56.2"),
		.package(url: "https://github.com/eu-digital-identity-wallet/eudi-lib-ios-statium-swift.git", exact: "0.6.1"),
		.package(url: "https://github.com/apple/swift-docc-plugin", from: "1.5.0"),
	],
	targets: [
		.target(
			name: "EudiWalletKit",
			dependencies: [
				.product(name: "MdocDataTransfer18013", package: "eudi-lib-ios-iso18013-data-transfer"),
				.product(name: "WalletStorage", package: "eudi-lib-ios-wallet-storage"),
				.product(name: "OpenID4VP", package: "eudi-lib-ios-openid4vp-swift"),
				.product(name: "OpenID4VCI", package: "eudi-lib-ios-openid4vci-swift"),
				.product(name: "eudi-lib-sdjwt-swift", package: "eudi-lib-sdjwt-swift"),
				.product(name: "StatiumSwift", package: "eudi-lib-ios-statium-swift"),
			]
		),
		.testTarget(
			name: "IBMVerifyDCTests",
			dependencies: ["EudiWalletKit"],
			resources: [.process("Resources")]
		),
	]
)
