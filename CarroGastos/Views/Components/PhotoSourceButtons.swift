import SwiftUI
import PhotosUI
import UIKit

/// Dois botões: tirar foto agora (câmera) ou escolher da galeria.
struct PhotoSourceButtons: View {
    var cameraTitle = "Tirar foto"
    var libraryTitle = "Escolher foto"
    let onImage: (UIImage) -> Void

    @State private var showingCamera = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 10) {
            Button {
                showingCamera = true
            } label: {
                Label(cameraTitle, systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(libraryTitle, systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .font(.rounded(15, .semibold))
        .controlSize(.large)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { image in onImage(image) }
                .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    onImage(image)
                }
                pickerItem = nil
            }
        }
    }
}

/// Câmera do iPhone (cai para a galeria no simulador).
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onImage: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
