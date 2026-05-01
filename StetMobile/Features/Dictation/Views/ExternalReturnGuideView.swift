import SwiftUI

struct ExternalReturnGuideView: View {
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 40) {
            // Close Button
            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
            }
            .padding(.top, 20)
            .padding(.horizontal, 24)
            
            Spacer()
            
            // Headline
            Text("Swipe back to your app")
                .font(.system(size: 32, weight: .bold, design: .serif))
                .multilineTextAlignment(.center)
            
            // Illustration (Mockup)
            VStack(spacing: 0) {
                ZStack {
                    // Phone Frame Mockup
                    RoundedRectangle(cornerRadius: 40)
                        .stroke(Color.black, lineWidth: 8)
                        .frame(width: 240, height: 260)
                        .background(
                            RoundedRectangle(cornerRadius: 40)
                                .fill(Color(.systemGray6))
                        )
                    
                    VStack(spacing: 20) {
                        // Waveform Placeholder
                        HStack(spacing: 4) {
                            ForEach(0..<6) { i in
                                Capsule()
                                    .fill(Color.black.opacity(0.7))
                                    .frame(width: 4, height: CGFloat([20, 40, 30, 50, 25, 35][i]))
                            }
                        }
                        
                        VStack(spacing: 4) {
                            Text("Listening")
                                .font(.caption2.bold())
                            Text("iPhone Microphone")
                                .font(.system(size: 8))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 20)
            
            // Description
            Text("We wish you didn't have to switch apps to use Typeless, but Apple now requires it to activate the microphone.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Spacer()
            
            // Bottom Action Indicator
            VStack(spacing: 12) {
                Text("Swipe right on the bar below")
                    .font(.subheadline.bold())
                
                ZStack {
                    Capsule()
                        .fill(Color.black)
                        .frame(width: 120, height: 4)
                    
                    Image(systemName: "hand.draw")
                        .font(.title3)
                        .offset(x: -40, y: 15)
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
    }
}

#Preview {
    ExternalReturnGuideView(onDismiss: {})
}
