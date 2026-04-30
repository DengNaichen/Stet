import SwiftUI

struct KeyboardView: View {
    var onMicTap: () -> Void
    var onKeyTap: (String) -> Void
    var onBackspace: () -> Void
    var onReturn: () -> Void
    var onNextKeyboard: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Top Row Functions
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    KeyboardButton(icon: "at", action: { onKeyTap("@") })
                    KeyboardButton(icon: "minus", action: { onKeyTap("_") })
                    //                    KeyboardButton(icon: "delete.left.fill", action: { onBackspace })
                    //                }
                }
                .padding(.horizontal)
                
                // Center Content
                VStack(spacing: 12) {
                    Text("Tap to speak")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Button(action: onMicTap) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 30))
                            .foregroundColor(.white)
                            .frame(width: 140, height: 64)
                            .background(Color.black)
                            .clipShape(Capsule())
                    }
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
