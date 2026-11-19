import SwiftUI
import SwiftData
import PhotosUI

/// Foto do carro (opcional). Sem foto, mostra só um botão discreto para adicionar.
struct CarPhotoButton: View {
    @Environment(\.modelContext) private var context
    let vehicle: Vehicle
    var size: CGFloat = 84

    @State private var image: UIImage?
    @State private var showingOptions = false
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var showingViewer = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var saving = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 18, style: .continuous) }

    var body: some View {
        Button {
            if image != nil { showingViewer = true } else { showingOptions = true }
        } label: {
            content
        }
        .buttonStyle(.plain)
        .accessibilityLabel(image == nil ? "Adicionar foto do carro" : "Ver foto do carro")
        .confirmationDialog("Foto do carro", isPresented: $showingOptions, titleVisibility: .visible) {
            // Pequena espera para o menu fechar antes de abrir a câmera/galeria.
            Button("Tirar foto") { after { showingCamera = true } }
            Button("Escolher da galeria") { after { showingLibrary = true } }
            if image != nil {
                Button("Remover foto", role: .destructive) { remove() }
            }
        }
        .photosPicker(isPresented: $showingLibrary, selection: $pickerItem, matching: .images)
        .fullScreenCover(isPresented: $showingCamera) {
            CameraPicker { save($0) }
                .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $showingViewer) {
            CarPhotoViewer(image: image) {
                showingViewer = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { showingOptions = true }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) {
                    save(picked)
                }
                pickerItem = nil
            }
        }
        .task(id: vehicle.uuid) { await loadImage() }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
                .overlay(alignment: .center) { if saving { ProgressView() } }
        } else {
            VStack(spacing: 5) {
                if saving {
                    ProgressView()
                } else {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Foto do\ncarro")
                        .font(.rounded(11, .semibold))
                        .multilineTextAlignment(.center)
                }
            }
            .foregroundStyle(Color.brand)
            .frame(width: size, height: size)
            .background(Color.brand.opacity(0.08), in: shape)
            .overlay(shape.strokeBorder(Color.brand.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
    }

    private func after(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }

    private func loadImage() async {
        let data = vehicle.photoData
        image = await Task.detached(priority: .userInitiated) {
            data.flatMap { UIImage(data: $0) }?.preparingForDisplay()
        }.value
    }

    private func save(_ picked: UIImage) {
        saving = true
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Data?, UIImage?) in
                let maxSide: CGFloat = 900
                let scale = min(1, maxSide / max(picked.size.width, picked.size.height))
                let size = CGSize(width: picked.size.width * scale, height: picked.size.height * scale)
                let resized = UIGraphicsImageRenderer(size: size).image { _ in
                    picked.draw(in: CGRect(origin: .zero, size: size))
                }
                return (resized.jpegData(compressionQuality: 0.75), resized)
            }.value
            vehicle.photoData = result.0
            try? context.save()
            image = result.1
            saving = false
            Haptics.success()
        }
    }

    private func remove() {
        vehicle.photoData = nil
        try? context.save()
        image = nil
    }
}

/// Foto em tela cheia, com opção de trocar.
struct CarPhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage?
    let onChange: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 8)
            }
            VStack {
                HStack {
                    Button("Fechar") { dismiss() }
                    Spacer()
                    Button("Trocar foto") { onChange() }
                }
                .font(.rounded(17, .semibold))
                .foregroundStyle(.white)
                .padding(20)
                Spacer()
            }
        }
    }
}
