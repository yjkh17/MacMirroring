import SwiftUI

struct MacScreenView: View {
    @ObservedObject var mirroringManager: MirroringManager
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    
    var body: some View {
        VStack {
            HStack {
                Button("Disconnect") {
                    mirroringManager.disconnect()
                }
                .buttonStyle(.bordered)
                
                Spacer()
                
                Text("Connected to Mac")
                    .foregroundColor(.green)
                    .font(.caption)
            }
            .padding()
            
            GeometryReader { geometry in
                ZStack {
                    Color.black
                        .cornerRadius(10)
                    
                    if let screenData = mirroringManager.screenData,
                       let uiImage = UIImage(data: screenData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(scale)
                            .offset(offset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            scale = value
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            offset = value.translation
                                        }
                                )
                            )
                    } else {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            
                            Text("Waiting for screen data...")
                                .foregroundColor(.white)
                                .padding(.top)
                        }
                    }
                }
            }
            .cornerRadius(10)
        }
    }
}