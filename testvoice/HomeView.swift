import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Stats Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        StatCard(icon: "clock", value: viewModel.totalHours, unit: "hr", value2: viewModel.totalMinutes, unit2: "min", label: "Total dictation time")
                        StatCard(icon: "mic", value: viewModel.wordsDictated, unit: "words", label: "Words dictated")
                        StatCard(icon: "hourglass", value: viewModel.timeSaved, unit: "hr", label: "Time saved")
                        StatCard(icon: "bolt.fill", value: viewModel.averageWPM, unit: "WPM", label: "Average dictation speed")
                    }
                    
                    // Upgrade Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Get unlimited words")
                            .font(.headline)
                        
                        VStack(spacing: 8) {
                            HStack {
                                Text("\(Int(viewModel.currentWords))")
                                    .font(.title2.bold())
                                Text("/")
                                    .foregroundStyle(.secondary)
                                Text("\(Int(viewModel.totalWordsLimit))")
                                    .font(.title2.bold())
                                    .foregroundStyle(.secondary)
                                Text("words")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            
                            ProgressView(value: viewModel.currentWords, total: viewModel.totalWordsLimit)
                                .tint(.black)
                                .background(Color(.systemGray5))
                                .clipShape(Capsule())
                        }
                        
                        Text("Upgrade for unlimited dictation and other Pro features.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        
                        Button(action: viewModel.upgradeToPro) {
                            Text("Upgrade")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 8) {
                        Image(systemName: "moon.fill") // Placeholder for the logo
                            .rotationEffect(.degrees(-45))
                        Text("Typeless")
                            .font(.title2.bold())
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Toggle("", isOn: .constant(false))
                        .labelsHidden()
                        .toggleStyle(SwitchToggleStyle(tint: .blue))
                }
            }
        }
    }
}

struct StatCard: View {
    let icon: String
    let value: String
    var unit: String = ""
    var value2: String? = nil
    var unit2: String? = nil
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
                .padding(8)
                .background(Color(.systemGray6))
                .clipShape(Circle())
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                Text(unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                if let v2 = value2, let u2 = unit2 {
                    Text(v2)
                        .font(.title2.bold())
                        .padding(.leading, 4)
                    Text(u2)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 10, x: 0, y: 5)
    }
}

#Preview {
    HomeView()
}
