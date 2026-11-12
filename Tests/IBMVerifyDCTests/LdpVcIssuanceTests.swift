import Foundation
import Testing
import OpenID4VCI
import WalletStorage
import MdocDataModel18013
import MdocSecurity18013
import SwiftyJSON
@testable import EudiWalletKit

/// `ldp_vc` (W3C JSON-LD, Data Integrity) issuance: offer resolution, absence of holder binding and storage of the issued credential.
@Suite("ldp_vc issuance")
struct LdpVcIssuanceTests {
	private static let issuerURL = "https://issuer.example.com"
	private static let identifier = "PermanentResidentCard_ldp"

	private static func issuerMetadataJson(withDisplay: Bool, metadataClaims: Bool) -> String {
		let display = withDisplay ? #""display": [{"name": "Permanent Resident Card", "locale": "en"}],"# : #""display": [],"#
		let claims = metadataClaims ? #""claims": [{"path": ["credentialSubject", "givenName"], "display": [{"name": "Given name", "locale": "en"}]}]"# : #""claims": []"#
		return """
		{
		  "credential_issuer": "\(issuerURL)",
		  "credential_endpoint": "\(issuerURL)/credential",
		  "credential_configurations_supported": {
		    "\(identifier)": {
		      "format": "ldp_vc",
		      "scope": "prc",
		      "credential_signing_alg_values_supported": ["eddsa-rdfc-2022"],
		      "credential_metadata": { \(display) \(claims) },
		      "@context": ["https://www.w3.org/ns/credentials/v2"],
		      "type": ["VerifiableCredential", "PermanentResidentCard"],
		      "credential_definition": {
		        "@context": ["https://www.w3.org/ns/credentials/v2"],
		        "type": ["VerifiableCredential", "PermanentResidentCard"],
		        "claims": [{"path": ["credentialSubject", "familyName"], "display": [{"name": "Family name", "locale": "en"}]}]
		      }
		    }
		  }
		}
		"""
	}

	private static func metadata(withDisplay: Bool = true, metadataClaims: Bool = true) throws -> CredentialIssuerMetadata {
		try JSONDecoder().decode(CredentialIssuerMetadata.self, from: Data(issuerMetadataJson(withDisplay: withDisplay, metadataClaims: metadataClaims).utf8))
	}

	private static func configuration(_ metadata: CredentialIssuerMetadata, service: OpenId4VciService) async throws -> CredentialConfiguration {
		try await service.getCredentialConfiguration(credentialIssuerIdentifier: issuerURL, issuerDisplay: [], credentialsSupported: metadata.credentialsSupported, identifier: identifier, docType: nil, vct: nil, batchCredentialIssuance: nil, dpopSigningAlgValuesSupported: nil, clientAttestationPopSigningAlgValuesSupported: nil)
	}

	private static func makeVciService(storageService: any DataStorageService = TestDataStorageService(), storage: StorageManager? = nil) throws -> OpenId4VciService {
		let config = OpenId4VciConfiguration(credentialIssuerURL: issuerURL)
		#if canImport(EudiEtsi1196x2)
		let trustConfig = TrustConfiguration(trustSource: .etsi(.eudiRef), defaultPolicy: .warning)
		#else
		let trustConfig = TrustConfiguration(rootIaca: [], defaultPolicy: .warning)
		#endif
		return try OpenId4VciService(uiCulture: nil, config: config, networking: TestNetworking(metadata: Data()), storage: storage ?? StorageManager(storageService: storageService), storageService: storageService, trustConfig: trustConfig, localAuthenticationContext: ThreadSafeAuthContext())
	}

	@Test("An ldp_vc offer entry yields an OfferedDocModel with the issuer's metadata claims")
	func offerEntryIsPreviewable() async throws {
		let metadata = try Self.metadata()
		let service = try Self.makeVciService()
		let infos = try await service.getCredentialOfferedModels(credentialsSupported: metadata.credentialsSupported, batchCredentialIssuance: nil)
		let offered = try #require(infos.first?.offered)
		#expect(infos.count == 1)
		#expect(offered.credentialConfigurationIdentifier == Self.identifier)
		#expect(offered.displayName == "Permanent Resident Card")
		#expect(offered.scope == "prc")
		#expect(offered.docType == nil && offered.vct == nil)
		#expect(offered.claims.count == 1)
		#expect(offered.claims.first?.path.value.count == 2)
		#expect(offered.docTypeIdentifier != nil)
	}

	@Test("Without display metadata the name falls back to the last non-VerifiableCredential type, and claims fall back to credential_definition")
	func fallbacks() async throws {
		let metadata = try Self.metadata(withDisplay: false, metadataClaims: false)
		let service = try Self.makeVciService()
		let offered = try #require(try await service.getCredentialOfferedModels(credentialsSupported: metadata.credentialsSupported, batchCredentialIssuance: nil).first?.offered)
		#expect(offered.displayName == "PermanentResidentCard")
		#expect(offered.claims.count == 1)
		#expect(offered.claims.first?.display?.first?.name == "Family name")
	}

	@Test("The ldp_vc configuration is resolved by identifier, uses the ldp_vc format and keeps cryptosuites out of the JWS algorithm list")
	func configurationIsResolved() async throws {
		let service = try Self.makeVciService()
		let config = try await Self.configuration(try Self.metadata(), service: service)
		#expect(config.format == .ldpVc)
		#expect(config.scope == "prc")
		#expect(config.credentialSigningAlgValuesSupported.isEmpty)
		#expect(config.requiresHolderBinding == false)
	}

	@Test("An unknown identifier is not resolved")
	func unknownIdentifierIsRejected() async throws {
		let metadata = try Self.metadata()
		let service = try Self.makeVciService()
		await #expect(throws: WalletError.self) {
			_ = try await service.getCredentialConfiguration(credentialIssuerIdentifier: Self.issuerURL, issuerDisplay: [], credentialsSupported: metadata.credentialsSupported, identifier: "Other", docType: nil, vct: nil, batchCredentialIssuance: nil, dpopSigningAlgValuesSupported: nil, clientAttestationPopSigningAlgValuesSupported: nil)
		}
	}

	@Test("initSecurityKeys creates no key batch and no binding key for ldp_vc")
	func noKeysAreCreated() async throws {
		let service = try Self.makeVciService()
		let config = try await Self.configuration(try Self.metadata(), service: service)
		let (bindingKeys, publicKeys) = try await service.initSecurityKeys(config, clientId: "client")
		#expect(bindingKeys.isEmpty && publicKeys.isEmpty)
	}

	private static let credentialJson = #"{"@context":["https://www.w3.org/ns/credentials/v2"],"type":["VerifiableCredential","PermanentResidentCard"],"issuer":"\#(issuerURL)","validFrom":"2024-01-01T00:00:00Z","credentialSubject":{"givenName":"JANE","familyName":"DOE"}}"#

	private static func authorizedRequest() throws -> AuthorizedRequest {
		AuthorizedRequest(accessToken: try IssuanceAccessToken(accessToken: "test-token", tokenType: .bearer), refreshToken: nil, credentialIdentifiers: nil, timeStamp: 0, dPopNonce: nil, grantType: nil)
	}

	private static func issueRequest() throws -> IssueRequest {
		SecureAreaRegistry.shared.register(secureArea: SoftwareSecureArea.create(storage: InMemorySecureKeyStorage()))
		return try IssueRequest(id: UUID().uuidString, credentialOptions: CredentialOptions(credentialPolicy: .rotateUse, batchSize: 1))
	}

	/// Issues the sample credential through `finalizeIssuing` and returns the stored document.
	private static func issueCredential(service: OpenId4VciService) async throws -> WalletStorage.Document {
		let config = try await configuration(try metadata(), service: service)
		let outcome = IssuanceOutcome.issued([(data: Data(credentialJson.utf8), publicKey: Data())], config, try authorizedRequest(), notificationId: nil)
		return try await service.finalizeIssuing(issueOutcome: outcome, docType: nil, format: .ldpVc, issueReq: try issueRequest(), deleteId: nil)
	}

	@Test("An issued ldp_vc credential is stored as JSON with the ldp_vc format and without key info, and gets a claims model")
	func issuedCredentialIsStoredWithoutKeys() async throws {
		let storageService = RecordingStorageService()
		let service = try Self.makeVciService(storageService: storageService)
		let doc = try await Self.issueCredential(service: service)

		#expect(doc.docDataFormat == .ldpVc)
		#expect(doc.docKeyInfo == nil)
		#expect(doc.docType == "prc")
		#expect(doc.data == Data(Self.credentialJson.utf8))
		let saved = await storageService.saved
		#expect(saved.count == 1)
		#expect(saved.first?.batch == nil)
		let model = try #require(StorageManager.toClaimsModel(doc: doc, uiCulture: nil))
		#expect(model.docDataFormat == .ldpVc)
		#expect(model.docClaims.map(\.name).sorted() == ["familyName", "givenName"])
		#expect(model.docClaims.first { $0.name == "givenName" }?.displayName == "Given name")
		#expect(model.docClaims.first { $0.name == "givenName" }?.path == ["credentialSubject", "givenName"])
		#expect(model.validFrom != nil)

		// Issuers send both plain and fractional-second timestamps, and the pre-VCDM2 field names
		var legacy = try JSON(data: Data(Self.credentialJson.utf8))
		legacy["validFrom"] = JSON.null
		legacy["issuanceDate"] = "2026-11-12T01:04:02Z"
		legacy["expirationDate"] = "2026-11-12T02:04:02.685Z"
		let legacyDoc = WalletStorage.Document(id: doc.id, docType: doc.docType, docDataFormat: .ldpVc, data: try legacy.rawData(), docKeyInfo: nil, createdAt: Date(), metadata: doc.metadata, displayName: nil, status: .issued)
		let legacyModel = try #require(StorageManager.toClaimsModel(doc: legacyDoc, uiCulture: nil))
		#expect(legacyModel.validFrom != nil)
		#expect(legacyModel.validUntil != nil)

		// The subject's JSON-LD `type` is hidden, and optional claims such as gender show once the issuer sets them
		var withOptional = legacy
		withOptional["credentialSubject"]["type"] = ["PermanentResident"]
		withOptional["credentialSubject"]["gender"] = "Female"
		withOptional["credentialSubject"]["commuterClassification"] = "C1"
		let optionalDoc = WalletStorage.Document(id: doc.id, docType: doc.docType, docDataFormat: .ldpVc, data: try withOptional.rawData(), docKeyInfo: nil, createdAt: Date(), metadata: doc.metadata, displayName: nil, status: .issued)
		let optionalModel = try #require(StorageManager.toClaimsModel(doc: optionalDoc, uiCulture: nil))
		#expect(optionalModel.docClaims.map(\.name).sorted() == ["commuterClassification", "familyName", "gender", "givenName"])
	}

	@Test("A JSON object credential response is accepted for ldp_vc with no holder keys, and rejected for other formats")
	func credentialResponseHandling() async throws {
		let service = try Self.makeVciService()
		let config = try await Self.configuration(try Self.metadata(), service: service)
		let credential = Credential.json(try JSON(data: Data(Self.credentialJson.utf8)))
		let outcome = try await OpenId4VciService.handleCredentialResponse(credentials: [credential], publicKeys: [], configuration: config, authorized: try Self.authorizedRequest(), notificationId: "n1", logger: logger)
		guard case let .issued(pairs, _, _, notificationId) = outcome else { Issue.record("Expected an issued outcome"); return }
		#expect(pairs.count == 1)
		#expect(pairs.first?.publicKey == Data())
		#expect(try JSON(data: try #require(pairs.first?.data))["credentialSubject"]["givenName"].string == "JANE")
		#expect(notificationId == "n1")

		let wrapped = Credential.json(JSON([["credential": try JSON(data: Data(Self.credentialJson.utf8)).object]]))
		let wrappedOutcome = try await OpenId4VciService.handleCredentialResponse(credentials: [wrapped], publicKeys: [], configuration: config, authorized: try Self.authorizedRequest(), notificationId: nil, logger: logger)
		guard case let .issued(wrappedPairs, _, _, _) = wrappedOutcome else { Issue.record("Expected an issued outcome"); return }
		#expect(wrappedPairs.count == 1)
		#expect(try JSON(data: try #require(wrappedPairs.first?.data))["credentialSubject"]["givenName"].string == "JANE")

		let asString = Credential.string(Self.credentialJson)
		let stringOutcome = try await OpenId4VciService.handleCredentialResponse(credentials: [asString], publicKeys: [], configuration: config, authorized: try Self.authorizedRequest(), notificationId: nil, logger: logger)
		guard case let .issued(stringPairs, _, _, _) = stringOutcome else { Issue.record("Expected an issued outcome"); return }
		#expect(try JSON(data: try #require(stringPairs.first?.data))["credentialSubject"]["givenName"].string == "JANE")

		let sdJwtConfig = CredentialConfiguration(configurationIdentifier: config.configurationIdentifier, credentialIssuerIdentifier: config.credentialIssuerIdentifier, vct: "urn:test", supportsAttestationProofType: false, supportsJwtProofTypeWithAttestation: false, credentialSigningAlgValuesSupported: ["ES256"], dpopSigningAlgValuesSupported: nil, clientAttestationPopSigningAlgValuesSupported: nil, issuerDisplay: [], display: [], claims: [], format: .sdjwt, defaultCredentialOptions: CredentialOptions(credentialPolicy: .rotateUse, batchSize: 1))
		await #expect(throws: WalletError.self) {
			_ = try await OpenId4VciService.handleCredentialResponse(credentials: [credential], publicKeys: [], configuration: sdJwtConfig, authorized: try Self.authorizedRequest(), notificationId: nil, logger: logger)
		}
	}

	@Test("A deferred ldp_vc is stored without key info, so it can be deleted")
	func deferredCredentialHasNoKeyInfo() async throws {
		let storageService = RecordingStorageService()
		let service = try Self.makeVciService(storageService: storageService)
		let config = try await Self.configuration(try Self.metadata(), service: service)
		let endpoint = try JSONDecoder().decode(CredentialIssuerEndpoint.self, from: Data(#""\#(Self.issuerURL)/deferred""#.utf8))
		let deferred = DeferredIssuanceModel(deferredCredentialEndpoint: endpoint, transactionId: try TransactionId(value: "tx-1"), publicKeys: [], derKeyData: nil, timeStamp: 0)
		let doc = try await service.finalizeIssuing(issueOutcome: .deferred(deferred, config, try Self.authorizedRequest()), docType: nil, format: .ldpVc, issueReq: try Self.issueRequest(), deleteId: nil)
		#expect(doc.status == .deferred)
		#expect(doc.docDataFormat == .ldpVc)
		#expect(doc.docKeyInfo == nil)
		#expect(doc.docTypeIdentifier == .identifier(Self.identifier))
	}

	@Test("A stored ldp_vc document maps to its configuration identifier, which pending issuance needs to resume")
	func docTypeIdentifierUsesConfigurationIdentifier() async throws {
		let service = try Self.makeVciService()
		let doc = try await Self.issueCredential(service: service)
		#expect(doc.docTypeIdentifier == .identifier(Self.identifier))
		let withoutMetadata = WalletStorage.Document(id: "x", docType: "prc", docDataFormat: .ldpVc, data: Data(), docKeyInfo: nil, createdAt: Date(), metadata: nil, displayName: nil, status: .pending)
		#expect(withoutMetadata.docTypeIdentifier == nil)
	}

	@Test("A document store holding an ldp_vc refreshes usage counters, reports a credential as available, is not presentable and can be deleted")
	func storageWithKeylessDocument() async throws {
		let storageService = RecordingStorageService()
		let storage = StorageManager(storageService: storageService)
		let service = try Self.makeVciService(storageService: storageService, storage: storage)
		let doc = try await Self.issueCredential(service: service)
		#expect(storage.docModels.count == 1)

		try await storage.refreshUsageCounters()
		#expect(try await storage.getCredentialsUsageCount(id: doc.id) == nil)
		#expect(try await storage.hasAnyCredential(id: doc.id))
		#expect(try await storage.getDocIdsToPresentInfo(documents: [doc]).isEmpty)
		#expect(doc.getClaimDisplayNames(nil) == nil)

		try await storage.deleteDocument(id: doc.id, status: .issued)
		#expect(storage.docModels.isEmpty)
	}
}

/// Records saved documents. Issued `ldp_vc` documents have no key batch, so `batch` must be nil.
private actor RecordingStorageService: DataStorageService {
	private(set) var saved: [(document: WalletStorage.Document, batch: [WalletStorage.Document]?)] = []
	func loadDocument(id: String, status: WalletStorage.DocumentStatus) async throws -> WalletStorage.Document? { nil }
	func loadDocumentMetadata(id: String, status: WalletStorage.DocumentStatus) async throws -> DocMetadata? { nil }
	func loadDocuments(status: WalletStorage.DocumentStatus) async throws -> [WalletStorage.Document]? { [] }
	func saveDocument(_ document: WalletStorage.Document, batch: [WalletStorage.Document]?, allowOverwrite: Bool) async throws { saved.append((document, batch)) }
	func deleteDocument(id: String, status: WalletStorage.DocumentStatus) async throws {}
	func deleteDocuments(status: WalletStorage.DocumentStatus) async throws {}
	func deleteDocumentCredential(id: String, index: Int) async throws {}
}
