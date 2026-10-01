import SwiftUI

enum AppState {
    case idle
    case fetching
    case ready
    case downloading
    case done
    case error
}

@MainActor
class ViewModel: ObservableObject {
    @Published var url: String = ""
    @Published var state: AppState = .idle
    @Published var videoInfo: VideoInfo?
    @Published var selectedLanguage: String = ""
    @Published var selectedQuality: String = "1080p"
    @Published var progress: Double = 0
    @Published var errorMessage: String = ""
    @Published var outputFile: String = ""
    @Published var outputDir: String = NSHomeDirectory() + "/Downloads"

    let qualities = ["1080p", "720p", "480p", "360p"]
    private let backend = YTLangBackend()

    func fetchInfo() {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        state = .fetching
        errorMessage = ""
        videoInfo = nil

        Task {
            do {
                let info = try await backend.fetchInfo(url: trimmed)
                videoInfo = info
                selectedLanguage = info.languages.first?.code ?? "en"
                state = .ready
            } catch {
                errorMessage = error.localizedDescription
                state = .error
            }
        }
    }

    func startDownload() {
        guard let info = videoInfo else { return }

        state = .downloading
        progress = 0
        errorMessage = ""

        Task {
            do {
                let file = try await backend.download(
                    url: url.trimmingCharacters(in: .whitespacesAndNewlines),
                    language: selectedLanguage,
                    quality: selectedQuality,
                    outputDir: outputDir,
                    title: info.title,
                    onProgress: { pct in
                        Task { @MainActor in
                            self.progress = pct
                        }
                    }
                )
                outputFile = file
                progress = 100
                state = .done
            } catch {
                errorMessage = error.localizedDescription
                state = .error
            }
        }
    }

    func revealInFinder() {
        let path = outputFile.isEmpty ? outputDir : outputFile
        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
    }

    func reset() {
        url = ""
        state = .idle
        videoInfo = nil
        progress = 0
        errorMessage = ""
        outputFile = ""
    }
}

struct ContentView: View {
    @StateObject private var vm = ViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 2) {
                Text("YT Lang Downloader")
                    .font(.system(size: 20, weight: .bold))
                Text("Download YouTube videos in any dubbed language")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 20)
            .padding(.bottom, 16)

            // URL input
            HStack(spacing: 8) {
                TextField("Paste YouTube URL...", text: $vm.url)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { vm.fetchInfo() }

                Button("Fetch") { vm.fetchInfo() }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || vm.state == .fetching || vm.state == .downloading)
            }
            .padding(.horizontal, 24)

            // Loading indicator for fetch
            if vm.state == .fetching {
                ProgressView("Fetching video info...")
                    .padding(.top, 24)
            }

            // Video info + options
            if let info = vm.videoInfo, vm.state == .ready || vm.state == .downloading || vm.state == .done {
                VStack(spacing: 16) {
                    // Video info card
                    HStack(alignment: .top, spacing: 12) {
                        AsyncImage(url: URL(string: info.thumbnail)) { image in
                            image.resizable().aspectRatio(contentMode: .fill)
                        } placeholder: {
                            Rectangle().fill(.quaternary)
                        }
                        .frame(width: 140, height: 79)
                        .clipShape(RoundedRectangle(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(info.title)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(2)
                            Text(info.durationString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(info.languages.count) languages available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(.background.shadow(.drop(radius: 1)), in: RoundedRectangle(cornerRadius: 8))

                    // Language + Quality pickers
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("LANGUAGE").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Picker("Language", selection: $vm.selectedLanguage) {
                                ForEach(info.languages) { lang in
                                    Text(lang.isDefault ? "\(lang.name) (original)" : lang.name)
                                        .tag(lang.code)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("QUALITY").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Picker("Quality", selection: $vm.selectedQuality) {
                                ForEach(vm.qualities, id: \.self) { q in
                                    Text(q).tag(q)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(vm.state == .downloading || vm.state == .done)

                    // Download button
                    if vm.state == .ready {
                        Button(action: vm.startDownload) {
                            Text("Download")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    // Progress
                    if vm.state == .downloading {
                        VStack(spacing: 8) {
                            ProgressView(value: vm.progress, total: 100) {
                                Text("Downloading...")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Text("\(Int(vm.progress))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }

                    // Done
                    if vm.state == .done {
                        VStack(spacing: 12) {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Download complete")
                                    .font(.system(size: 13, weight: .semibold))
                            }

                            HStack(spacing: 8) {
                                Button("Show in Finder") { vm.revealInFinder() }
                                    .buttonStyle(.bordered)
                                Button("Download Another") { vm.reset() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
            }

            // Error
            if vm.state == .error {
                VStack(spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Error")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text(vm.errorMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)

                    Button("Try Again") { vm.state = .idle }
                        .buttonStyle(.bordered)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
