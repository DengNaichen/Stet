import SwiftUI

struct KeyboardView: View {
    var onMicDown: () -> Void
    var onMicUp: () -> Void
    var onKeyTap: (String) -> Void
    var onBackspace: () -> Void
    var onReturn: () -> Void
    var onNextKeyboard: () -> Void
    
    @State private var isPressing = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Top Row Functions
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    KeyboardButton(icon: "at", action: { onKeyTap("@") })
                    KeyboardButton(icon: "minus", action: { onKeyTap("_") })
                }
                .padding(.horizontal)
                
                // Center Content
                VStack(spacing: 12) {
                    Text(isPressing ? "Release to stop" : "Hold to speak")
                        .font(.subheadline)
                        .foregroundColor(isPressing ? .red : .secondary)
                    
                    Image(systemName: "mic.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .frame(width: 140, height: 64)
                        .background(isPressing ? Color.red : Color.black)
                        .clipShape(Capsule())
                        .scaleEffect(isPressing ? 1.1 : 1.0)
                        .animation(.spring(), value: isPressing)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !isPressing {
                                        isPressing = true
                                        onMicDown()
                                    }
                                }
                                .onEnded { _ in
                                    isPressing = false
                                    onMicUp()
                                }
                        )
                }
                
                // Bottom Row
                VStack(spacing: 15) {
                    Button(action: onReturn) {
                        Text("return")
                            .font(.body)
                            .foregroundColor(.black)
                            .frame(width: 120, height: 44)
                            .background(Color(.systemGray4))
                            .clipShape(Capsule())
                    }
                    
                    HStack {
                        Button(action: onNextKeyboard) {
                            Image(systemName: "globe")
                                .font(.title2)
                                .foregroundColor(.black)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGray6))
        }
    }
    
    struct KeyboardButton: View {
        let icon: String
        let action: () -> Void
        
        var body: some View {
            Button(action: action) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundColor(.black)
                    .frame(width: 44, height: 44)
                    .background(Color(.systemGray4))
                    .clipShape(Circle())
            }
        }
    }
}
