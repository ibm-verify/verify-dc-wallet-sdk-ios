import Foundation
import MdocDataModel18013
import MdocDataTransfer18013
import OpenID4VP
import SwiftyJSON
import Testing
import struct OpenID4VP.ClaimPath
import enum OpenID4VP.ClaimPathElement

@testable import EudiWalletKit

/// Presentation of `ldp_vc` credentials: DCQL matching, claim paths and holder-binding rules.
struct LdpVcPresentationTests {

	private let credentialJson = """
	{
	  "@context": ["https://www.w3.org/ns/credentials/v2", "https://example.org/ctx/v1"],
	  "type": ["VerifiableCredential", "UniversityDegreeCredential"],
	  "issuer": "did:example:issuer",
	  "credentialSubject": {"degree": {"name": "Bachelor of Science"}, "given_name": "Ada"}
	}
	"""

	private func dcql(typeValues: String = #"[["https://example.org/ctx/v1#UniversityDegreeCredential"]]"#, binding: String = "", claims: String = "") throws -> DCQL {
		let json = """
		{"credentials": [{"id": "ldp_vc_credential", "format": "ldp_vc", "meta": {"type_values": \(typeValues)}\(binding)\(claims)}]}
		"""
		return try JSONDecoder().decode(DCQL.self, from: Data(json.utf8))
	}

	private func queryable(types: [String]? = nil) throws -> DefaultDcqlQueryable {
		let credential = try JSON(data: Data(credentialJson.utf8))
		var paths = [String: [ClaimPath]](); var values = [String: [ClaimPath: [String]]]()
		OpenId4VpUtils.makeLdpVcClaimData(from: ["vc": credential], claimPaths: &paths, claimValues: &values)
		return DefaultDcqlQueryable(credentials: ["vc": ("UniversityDegree", .ldpVc)], claimPaths: paths, claimValues: values,
			ldpTypes: ["vc": types ?? OpenId4VpUtils.ldpCredentialTypes(credential)])
	}

	@Test("ldp_vc query reads its format and type from type_values")
	func formatAndType() throws {
		let query = try dcql().credentials[0]
		#expect(query.dataFormat == .ldpVc)
		#expect(query.ldpTypeValues == [["https://example.org/ctx/v1#UniversityDegreeCredential"]])
		#expect(query.docTypeOrVct == "UniversityDegreeCredential")
	}

	@Test("An unbound request resolves to the stored credential")
	func resolvesUnbound() throws {
		let result = try OpenId4VpUtils.resolveDcql(dcql(binding: #", "require_cryptographic_holder_binding": false"#), queryable: queryable())
		#expect(result.values.first?.first?.credentialId == "vc")
	}

	@Test("A binding-required request is not satisfied by an unbound credential")
	func bindingRequiredIsRejected() throws {
		for binding in ["", #", "require_cryptographic_holder_binding": true"#] {
			#expect(throws: WalletError.self) { try OpenId4VpUtils.resolveDcql(dcql(binding: binding), queryable: queryable()) }
		}
	}

	@Test("A different credential type is not found")
	func typeMismatch() throws {
		let request = try dcql(typeValues: #"[["https://example.org/ctx/v1#DrivingLicence"]]"#, binding: #", "require_cryptographic_holder_binding": false"#)
		#expect(throws: WalletError.self) { try OpenId4VpUtils.resolveDcql(request, queryable: queryable()) }
	}

	@Test("Every type of an alternative must be present; any alternative may match")
	func typeAlternatives() {
		let types = ["VerifiableCredential", "UniversityDegreeCredential"]
		#expect(OpenId4VpUtils.ldpTypesMatch(types, typeValues: [["UniversityDegreeCredential"]]))
		#expect(OpenId4VpUtils.ldpTypesMatch(types, typeValues: [["Other"], ["VerifiableCredential", "UniversityDegreeCredential"]]))
		#expect(!OpenId4VpUtils.ldpTypesMatch(types, typeValues: [["VerifiableCredential", "Other"]]))
		#expect(!OpenId4VpUtils.ldpTypesMatch(types, typeValues: []))
	}

	@Test("Claim paths start at the credential root")
	func claimPathsAreRooted() throws {
		let request = try dcql(binding: #", "require_cryptographic_holder_binding": false"#,
			claims: #", "claims": [{"path": ["credentialSubject", "degree", "name"]}]"#)
		let result = try OpenId4VpUtils.resolveDcql(request, queryable: queryable())
		#expect(result.values.first?.first?.claimQueries.count == 1)
		let missing = try dcql(binding: #", "require_cryptographic_holder_binding": false"#,
			claims: #", "claims": [{"path": ["credentialSubject", "missing"]}]"#)
		#expect(throws: WalletError.self) { try OpenId4VpUtils.resolveDcql(missing, queryable: queryable()) }
	}

	@Test("Claim values are matched")
	func claimValues() throws {
		let match = try dcql(binding: #", "require_cryptographic_holder_binding": false"#,
			claims: #", "claims": [{"path": ["credentialSubject", "given_name"], "values": ["Ada"]}]"#)
		#expect(throws: Never.self) { try OpenId4VpUtils.resolveDcql(match, queryable: queryable()) }
		let mismatch = try dcql(binding: #", "require_cryptographic_holder_binding": false"#,
			claims: #", "claims": [{"path": ["credentialSubject", "given_name"], "values": ["Bob"]}]"#)
		#expect(throws: WalletError.self) { try OpenId4VpUtils.resolveDcql(mismatch, queryable: queryable()) }
	}

	@Test("The transaction log records the requested ldp_vc paths")
	func presentedClaims() throws {
		let credential = try JSON(data: Data(credentialJson.utf8))
		let all = OpenId4VpService.ldpVcPresentedClaims(credential, docType: "UniversityDegree", items: [])
		#expect(all.first?.credentialIdentifier == "UniversityDegree")
		#expect(all.first?.claims.isEmpty == false)
		let some = OpenId4VpService.ldpVcPresentedClaims(credential, docType: "UniversityDegree", items: [RequestItem(elementPath: ["credentialSubject", "given_name"])])
		#expect(some.first?.claims.count == 1)
	}

	@Test("parseDcqlFormats keys ldp_vc requests by the stored doc type")
	func formatsRequested() throws {
		let request = try dcql()
		let parsed = try OpenId4VpUtils.parseDcqlFormats(request, idsToDocTypes: ["vc": "UniversityDegree", "mdoc": "org.iso.18013.5.1.mDL"], dataFormats: ["vc": .ldpVc, "mdoc": .cbor])
		#expect(parsed.formatsRequested == ["UniversityDegree": .ldpVc])
		#expect(parsed.inputDescriptorMap == ["UniversityDegree": "ldp_vc_credential"])
	}

	@Test("The credential is wrapped in an unsigned presentation with one verifiableCredential entry")
	func presentationWrapper() throws {
		let credential = try JSON(data: Data(credentialJson.utf8))
		let vp = OpenId4VpService.ldpVcPresentation(wrapping: credential)
		#expect(vp["type"].arrayValue.compactMap(\.string) == ["VerifiablePresentation"])
		#expect(vp["@context"].arrayValue.compactMap(\.string) == ["https://www.w3.org/ns/credentials/v2"])
		#expect(vp["verifiableCredential"].arrayValue.count == 1)
		#expect(vp["verifiableCredential"][0] == credential)
		#expect(!vp["proof"].exists())
	}

	@Test("A query without type_values cannot be resolved")
	func missingTypeValues() throws {
		let json = #"{"credentials": [{"id": "ldp_vc_credential", "format": "ldp_vc", "meta": {}, "require_cryptographic_holder_binding": false}]}"#
		let request = try? JSONDecoder().decode(DCQL.self, from: Data(json.utf8))
		// either the library rejects the query when decoding, or resolution fails with a WalletError
		if let request {
			#expect(throws: WalletError.self) { try OpenId4VpUtils.resolveDcql(request, queryable: queryable()) }
		}
		let empty = try dcql(typeValues: "[]", binding: #", "require_cryptographic_holder_binding": false"#)
		#expect(throws: WalletError.self) { try OpenId4VpUtils.resolveDcql(empty, queryable: queryable()) }
	}

	@Test("A mixed query resolves ldp_vc, dc+sd-jwt and mso_mdoc credentials independently")
	func mixedQuery() throws {
		let json = """
		{"credentials": [
		  {"id": "mdl", "format": "mso_mdoc", "meta": {"doctype_value": "org.iso.18013.5.1.mDL"}, "claims": [{"path": ["org.iso.18013.5.1", "family_name"]}]},
		  {"id": "pid", "format": "dc+sd-jwt", "meta": {"vct_values": ["urn:eudi:pid:1"]}, "claims": [{"path": ["family_name"]}]},
		  {"id": "ldp_vc_credential", "format": "ldp_vc", "meta": {"type_values": [["https://example.org/ctx/v1#UniversityDegreeCredential"]]}, "require_cryptographic_holder_binding": false, "claims": [{"path": ["credentialSubject", "given_name"]}]}
		]}
		"""
		let request = try JSONDecoder().decode(DCQL.self, from: Data(json.utf8))
		let credential = try JSON(data: Data(credentialJson.utf8))
		var paths = [String: [ClaimPath]](); var values = [String: [ClaimPath: [String]]]()
		OpenId4VpUtils.makeLdpVcClaimData(from: ["vc": credential], claimPaths: &paths, claimValues: &values)
		paths["mdl"] = [ClaimPath([.claim(name: "org.iso.18013.5.1"), .claim(name: "family_name")])]
		paths["pid"] = [ClaimPath([.claim(name: "family_name")])]
		let queryable = DefaultDcqlQueryable(
			credentials: ["mdl": ("org.iso.18013.5.1.mDL", .cbor), "pid": ("urn:eudi:pid:1", .sdjwt), "vc": ("UniversityDegree", .ldpVc)],
			claimPaths: paths, claimValues: values, ldpTypes: ["vc": OpenId4VpUtils.ldpCredentialTypes(credential)])
		let result = try OpenId4VpUtils.resolveDcql(request, queryable: queryable)
		let selections = result.values.flatMap { $0 }
		#expect(Set(selections.map(\.credentialId)) == ["mdl", "pid", "vc"])
		#expect(selections.first { $0.credentialId == "vc" }?.queryId.value == "ldp_vc_credential")
	}
}
