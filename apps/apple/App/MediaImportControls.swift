import AVFoundation
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import MandalaCore

struct MediaImportControls: View {
    let draftID: UUID
    @EnvironmentObject private var workspace: Workspace
    @Environment(\.words) private var words
    @State private var photoSelection: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var usingCamera = false
    @State private var choosingFile = false
    @State private var importing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { buttons }
                    .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 8) { buttons }
            }
            .buttonStyle(.bordered)
            .disabled(importing)

            if importing { ProgressView(words("working")) }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photoSelection,
                      matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            photoSelection = nil
            Task { await importPhoto(item) }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.item]) { result in
            switch result {
            case .success(let url): Task { await workspace.addFile(url) }
            case .failure(let error): errorMessage = words.error(error)
            }
        }
        .fullScreenCover(isPresented: $usingCamera) {
            CameraPicker { result in
                usingCamera = false
                if let result { store(result) }
            }.ignoresSafeArea()
        }
        .alert(words("error.title"), isPresented: Binding(get: { errorMessage != nil },
                                                          set: { if !$0 { errorMessage = nil } })) {
            Button(words("ok"), role: .cancel) { errorMessage = nil }
        } message: {
            if let errorMessage { Text(verbatim: errorMessage) }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        Button { choosingPhoto = true } label: {
            Label(words("media.library"), systemImage: "photo.on.rectangle")
        }.accessibilityIdentifier("media-library")
        Button { Task { await openCamera() } } label: {
            Label(words("media.camera"), systemImage: "camera")
        }.accessibilityIdentifier("media-camera")
        Button { choosingFile = true } label: {
            Label(words("resource.attach"), systemImage: "folder")
        }.accessibilityIdentifier("media-file")
    }

    private func importPhoto(_ item: PhotosPickerItem) async {
        importing = true
        defer { importing = false }
        do {
            guard let media = try await item.loadTransferable(type: ImportedMedia.self) else {
                errorMessage = words("media.importFailed")
                return
            }
            store(.success(media))
        } catch { errorMessage = words.error(error) }
    }

    private func openCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            errorMessage = words("media.cameraUnavailable")
            return
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        var allowed = status == .authorized
        if status == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
        guard allowed else {
            errorMessage = words("media.cameraDenied")
            return
        }
        usingCamera = true
    }

    private func store(_ result: Result<ImportedMedia, Error>) {
        do {
            let media = try result.get()
            try workspace.addAttachment(media.data, named: media.name, type: media.type, to: draftID)
        } catch { errorMessage = words.error(error) }
    }
}

private struct ImportedMedia: Transferable, Sendable {
    let data: Data
    let name: String
    let type: UTType

    init(data: Data, name: String, type: UTType) {
        self.data = data
        self.name = name
        self.type = type
    }

    init(file: URL, conformingTo category: UTType) throws {
        let data = try ProjectDisk.fileData(file)
        let fileType = UTType(filenameExtension: file.pathExtension, conformingTo: category)
        let advertised = try? file.resourceValues(forKeys: [.contentTypeKey]).contentType
        let imageType = category == .image && fileType?.isDynamic != false
            ? CGImageSourceCreateWithData(data as CFData, nil).flatMap(CGImageSourceGetType).flatMap { UTType($0 as String) }
            : nil
        guard let type = [fileType, advertised, imageType].compactMap({ $0 }).first(where: {
            $0.conforms(to: category) && !$0.isDynamic && $0.preferredFilenameExtension != nil
        }), let ext = type.preferredFilenameExtension else {
            throw ProjectError.invalidResource(file.lastPathComponent)
        }
        let name = file.pathExtension.isEmpty ? file.lastPathComponent + "." + ext : file.lastPathComponent
        self.init(data: data, name: name, type: type)
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { file in
            try ImportedMedia(file: file.file, conformingTo: .image)
        }
        FileRepresentation(importedContentType: .movie) { file in
            try ImportedMedia(file: file.file, conformingTo: .movie)
        }
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    var completion: (Result<ImportedMedia, Error>?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        let available = UIImagePickerController.availableMediaTypes(for: .camera) ?? [UTType.image.identifier]
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier].filter(available.contains)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {
        context.coordinator.completion = completion
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var completion: (Result<ImportedMedia, Error>?) -> Void
        init(completion: @escaping (Result<ImportedMedia, Error>?) -> Void) { self.completion = completion }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            completion(nil)
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let url = info[.mediaURL] as? URL {
                Task {
                    do {
                        let media = try await Task.detached {
                            try ImportedMedia(file: url, conformingTo: .movie)
                        }.value
                        completion(.success(media))
                    } catch { completion(.failure(error)) }
                }
            } else if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.94) {
                completion(.success(ImportedMedia(data: data, name: "IMG_" + UUID().uuidString.prefix(8) + ".jpg", type: .jpeg)))
            } else { completion(.failure(ProjectError.invalidResource("camera"))) }
        }
    }
}
