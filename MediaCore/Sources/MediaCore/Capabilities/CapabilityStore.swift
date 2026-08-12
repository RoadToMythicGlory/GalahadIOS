import Foundation

public struct SelectablePreset: Sendable, Equatable, Identifiable {
    public var id: String { preset.id }
    public var preset: QualityPreset
    /// False when exposed only via DEBUG lab/stub mode.
    public var isProductionStartable: Bool

    public init(preset: QualityPreset, isProductionStartable: Bool) {
        self.preset = preset
        self.isProductionStartable = isProductionStartable
    }
}

/// Permissions, encoder/transport availability, and validated preset allow-list.
public actor CapabilityStore {
    public private(set) var cameraAuthorized = false
    public private(set) var microphoneAuthorized = false
    public private(set) var broadcastAvailable = true
    public private(set) var stubEncoderAvailable = true
    public private(set) var hevcEncoderAvailable = false
    public private(set) var gstreamerSrtAvailable = false
    public private(set) var validatedPresetIds: Set<String> = []
    public private(set) var labStubModeEnabled: Bool
    public private(set) var lastProbeDetail: String?

    public init(labStubModeEnabled: Bool? = nil) {
        #if DEBUG
        self.labStubModeEnabled = labStubModeEnabled ?? true
        #else
        self.labStubModeEnabled = labStubModeEnabled ?? false
        #endif
    }

    public func setPermissions(camera: Bool, microphone: Bool, broadcast: Bool = true) {
        cameraAuthorized = camera
        microphoneAuthorized = microphone
        broadcastAvailable = broadcast
    }

    public func setEncoderAvailability(stub: Bool = true, hevc: Bool) {
        stubEncoderAvailable = stub
        hevcEncoderAvailable = hevc
    }

    public func setGStreamerSrtAvailable(_ available: Bool, detail: String? = nil) {
        gstreamerSrtAvailable = available
        lastProbeDetail = detail
    }

    public func setValidatedPresetIds(_ ids: Set<String>) {
        validatedPresetIds = ids
    }

    public func setLabStubModeEnabled(_ enabled: Bool) {
        labStubModeEnabled = enabled
    }

    public var encoderAdapterAvailable: Bool {
        stubEncoderAvailable || hevcEncoderAvailable
    }

    public func selectablePresets(productionOnly: Bool) -> [SelectablePreset] {
        if productionOnly {
            return QualityPreset.catalog
                .filter { validatedPresetIds.contains($0.id) }
                .map { SelectablePreset(preset: $0, isProductionStartable: true) }
        }
        if labStubModeEnabled {
            return QualityPreset.catalog.map { preset in
                SelectablePreset(
                    preset: preset,
                    isProductionStartable: validatedPresetIds.contains(preset.id)
                )
            }
        }
        return QualityPreset.catalog
            .filter { validatedPresetIds.contains($0.id) }
            .map { SelectablePreset(preset: $0, isProductionStartable: true) }
    }

    /// Production start requires validated preset + real HEVC + GStreamer SRT (unless lab stub).
    public func canStartProduction(presetId: String) -> Bool {
        validatedPresetIds.contains(presetId)
            && gstreamerSrtAvailable
            && hevcEncoderAvailable
    }

    public func canStartLabStub(presetId: String) -> Bool {
        labStubModeEnabled && QualityPreset.find(id: presetId) != nil && stubEncoderAvailable
    }

    public func assertStartAllowed(presetId: String, preferProduction: Bool) throws {
        if preferProduction {
            guard canStartProduction(presetId: presetId) else {
                throw MediaCoreError.presetNotAllowed(presetId)
            }
            return
        }
        if canStartProduction(presetId: presetId) { return }
        guard canStartLabStub(presetId: presetId) else {
            throw MediaCoreError.presetNotAllowed(presetId)
        }
    }
}
