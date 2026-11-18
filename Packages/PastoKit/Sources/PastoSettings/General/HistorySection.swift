import AppKit
import PastoUI
import SwiftUI

/// "Keep History": the capacity slider, what the store holds and the button that erases it.
struct HistorySection: View {
    @Bindable var model: HistoryModel
    @State private var isConfirmingErase = false

    var body: some View {
        SettingsSection(title: SettingsStrings.keepHistoryTitle) {
            VStack(spacing: SettingsMetrics.sliderBlockSpacing) {
                HistoryCapacitySlider(
                    model: model.capacity,
                    accessibilityLabel: SettingsStrings.keepHistoryTitle,
                    unlimitedText: SettingsStrings.unlimited
                )
                // While the knob is held, its value takes the place of the tick names.
                if model.capacity.isTracking {
                    Text(HistoryCapacityText.value(forDays: model.capacity.shownDays) ?? SettingsStrings.unlimited)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    tickLabels
                }
                if model.capacity.shownDays == 0 {
                    Label(SettingsStrings.unlimitedWarning, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack {
                Text(storageSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(SettingsStrings.eraseHistory) { isConfirmingErase = true }
            }
        }
        .alert(SettingsStrings.reduceHistoryTitle, isPresented: isConfirmingCapacity) {
            Button(SettingsStrings.delete, action: model.capacity.confirmPendingCapacity)
            Button(SettingsStrings.cancel, role: .cancel, action: model.capacity.discardPendingCapacity)
        } message: {
            Text(SettingsStrings.historyDeletionMessage)
        }
        .alert(SettingsStrings.eraseHistoryTitle, isPresented: $isConfirmingErase) {
            Button(SettingsStrings.erase, action: model.eraseHistory)
            Button(SettingsStrings.cancel, role: .cancel) {}
        } message: {
            Text(SettingsStrings.historyDeletionMessage)
        }
    }

    private var tickLabels: some View {
        let labels = HistoryCapacityText.unitTickLabels + [SettingsStrings.forever]
        return SliderTickLabelsLayout(tickInset: HistoryCapacitySlider.tickMarkInset) {
            ForEach(labels.indices, id: \.self) { index in
                Text(labels[index])
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private var storageSummary: String {
        SettingsStrings.storageSummary(
            items: SettingsStrings.itemCount(model.itemCount),
            size: model.storeSize.formatted(.byteCount(style: .file))
        )
    }

    /// An alert that goes away without a button (the window closing, say) leaves the limit as it
    /// was. It is put back a turn later, so a button's own action always runs first.
    private var isConfirmingCapacity: Binding<Bool> {
        Binding(
            get: { model.capacity.pendingDays != nil },
            set: { isPresented in
                guard !isPresented else { return }
                Task { model.capacity.discardPendingCapacity() }
            }
        )
    }
}
