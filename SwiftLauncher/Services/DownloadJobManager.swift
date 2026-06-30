import Foundation

@MainActor
@Observable
final class DownloadJobManager {
    private(set) var jobs: [DownloadTaskInfo] = []

    var activeJobs: [DownloadTaskInfo] {
        jobs.filter(\.isActive)
    }

    var hasActiveJobs: Bool {
        jobs.contains(where: \.isActive)
    }

    func hasActiveJob(for instanceID: UUID) -> Bool {
        jobs.contains { $0.instanceID == instanceID && $0.isActive }
    }

    @discardableResult
    func run(
        kind: DownloadJobKind,
        title: String,
        detail: String,
        instanceID: UUID? = nil,
        operation: (DownloadJobReporter) async throws -> Void
    ) async -> DownloadJobResult {
        let id = begin(kind: kind, title: title, detail: detail, instanceID: instanceID)
        let reporter = DownloadJobReporter(
            updateHandler: { [weak self] progress, detail, phase in
                self?.update(id, progress: progress, detail: detail, phase: phase)
            },
            attachHandler: { [weak self] instanceID in
                self?.attach(id, to: instanceID)
            }
        )

        do {
            update(id, progress: 0, detail: detail, phase: .preparing)
            try Task.checkCancellation()
            try await operation(reporter)
            complete(id)
            return .completed
        } catch is CancellationError {
            cancel(id)
            return .cancelled
        } catch {
            fail(id, error: error)
            return .failed(error)
        }
    }

    func clearCompleted() {
        jobs.removeAll { $0.state == .completed || $0.state == .cancelled }
    }

    private func begin(
        kind: DownloadJobKind,
        title: String,
        detail: String,
        instanceID: UUID?
    ) -> UUID {
        let now = Date()
        let job = DownloadTaskInfo(
            kind: kind,
            phase: .preparing,
            instanceID: instanceID,
            title: title,
            detail: detail,
            state: .queued,
            createdAt: now,
            updatedAt: now
        )
        jobs.insert(job, at: 0)
        return job.id
    }

    private func update(
        _ id: UUID,
        progress: Double,
        detail: String,
        phase: DownloadJobPhase?
    ) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].progress = min(max(progress, 0), 1)
        jobs[index].detail = detail
        jobs[index].state = .downloading
        if let phase {
            jobs[index].phase = phase
        }
        jobs[index].updatedAt = .now
    }

    private func attach(_ id: UUID, to instanceID: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].instanceID = instanceID
        jobs[index].updatedAt = .now
    }

    private func complete(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].progress = 1
        jobs[index].state = .completed
        jobs[index].phase = .finalizing
        jobs[index].updatedAt = .now
    }

    private func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .cancelled
        jobs[index].detail = "任务已取消"
        jobs[index].updatedAt = .now
    }

    private func fail(_ id: UUID, error: Error) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[index].state = .failed
        jobs[index].errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        jobs[index].updatedAt = .now
    }
}

struct DownloadJobReporter {
    private let updateHandler: @MainActor (Double, String, DownloadJobPhase?) -> Void
    private let attachHandler: @MainActor (UUID) -> Void

    init(
        updateHandler: @escaping @MainActor (Double, String, DownloadJobPhase?) -> Void,
        attachHandler: @escaping @MainActor (UUID) -> Void
    ) {
        self.updateHandler = updateHandler
        self.attachHandler = attachHandler
    }

    @MainActor
    func update(_ progress: Double, _ detail: String, phase: DownloadJobPhase? = nil) {
        updateHandler(progress, detail, phase)
    }

    @MainActor
    func attachToInstance(_ instanceID: UUID) {
        attachHandler(instanceID)
    }
}

enum DownloadJobResult {
    case completed
    case cancelled
    case failed(Error)

    var succeeded: Bool {
        if case .completed = self { return true }
        return false
    }
}
