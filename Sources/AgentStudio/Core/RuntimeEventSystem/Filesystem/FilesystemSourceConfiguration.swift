import Foundation

struct FilesystemHostAuthorizedRootInput: Sendable {
    // This is a provenance contract at the source-configuration boundary, not a
    // runtime authentication token. The host composition owner may construct it
    // only after authorizing the boundary and selected root.
    let registration: FSEventRegistrationToken
    let authorizedBoundary: URL
    let registeredRoot: URL
}

struct FilesystemUntrustedRootEvidence: Hashable, Sendable {
    let path: String
}

enum FilesystemUntrustedRootAuthorityKind: Hashable, Sendable {
    case rawPath
    case scannerResult
    case gitMetadata
    case callbackPayload
}

enum FilesystemRootAuthorityAttempt: Sendable {
    case hostAuthorized(FilesystemHostAuthorizedRootInput)
    case rawPath(FilesystemUntrustedRootEvidence)
    case scannerResult(FilesystemUntrustedRootEvidence)
    case gitMetadata(FilesystemUntrustedRootEvidence)
    case callbackPayload(FilesystemUntrustedRootEvidence)
}

enum FilesystemSourceConfigurationError: Error, Equatable, Sendable {
    case untrustedAuthority(FilesystemUntrustedRootAuthorityKind)
    case authorizedBoundaryNotAbsoluteFileURL
    case registeredRootNotAbsoluteFileURL
    case registeredRootOutsideAuthorizedBoundary
    case registeredRootUnavailable
    case registeredRootIsNotDirectory
    case registeredRootIsNotOnLocalVolume
    case ambiguousVolumeIdentity
    case ambiguousVolumeCasePolicy
    case unsupportedLocalVolumeFormat(String)
    case registrationMismatch(
        expected: FSEventRegistrationToken,
        submitted: FSEventRegistrationToken
    )
}

struct RegisteredRootDescriptor: Hashable, Sendable {
    let registration: FSEventRegistrationToken
    let aliases: FilesystemRegisteredRootAliases
    let volumeSemantics: FilesystemVolumeSemantics

    var sourceID: FilesystemSourceID { registration.sourceID }

    // Keep construction beside the exhaustive authority-attempt admission below.
    // Scanner, Git, callback, and raw-path APIs can carry evidence but cannot call
    // this initializer directly.
    fileprivate init(
        registration: FSEventRegistrationToken,
        canonicalizedRoot: FilesystemCanonicalizedAuthorizedRoot
    ) {
        self.registration = registration
        self.aliases = canonicalizedRoot.aliases
        self.volumeSemantics = canonicalizedRoot.volumeSemantics
    }

    func requireExactRegistration(_ submitted: FSEventRegistrationToken) throws {
        guard submitted == registration else {
            throw FilesystemSourceConfigurationError.registrationMismatch(
                expected: registration,
                submitted: submitted
            )
        }
    }
}

enum FilesystemSourceConfiguration {
    static func registerRoot(
        from authorityAttempt: FilesystemRootAuthorityAttempt,
        canonicalizer: FilesystemPathCanonicalizer = FilesystemPathCanonicalizer()
    ) throws -> RegisteredRootDescriptor {
        switch authorityAttempt {
        case .hostAuthorized(let input):
            let canonicalizedRoot = try canonicalizer.canonicalizeAuthorizedRoot(
                authorizedBoundary: input.authorizedBoundary,
                registeredRoot: input.registeredRoot
            )
            return RegisteredRootDescriptor(
                registration: input.registration,
                canonicalizedRoot: canonicalizedRoot
            )
        case .rawPath:
            throw FilesystemSourceConfigurationError.untrustedAuthority(.rawPath)
        case .scannerResult:
            throw FilesystemSourceConfigurationError.untrustedAuthority(.scannerResult)
        case .gitMetadata:
            throw FilesystemSourceConfigurationError.untrustedAuthority(.gitMetadata)
        case .callbackPayload:
            throw FilesystemSourceConfigurationError.untrustedAuthority(.callbackPayload)
        }
    }
}
