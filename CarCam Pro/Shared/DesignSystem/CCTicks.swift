import SwiftUI

/// Horizontal tick scale — major ticks every `major` steps.
/// Used beneath numeric readouts to imply a range without committing to one.
struct CCTicks: View {
    var count: Int = 20
    var major: Int = 5
    var height: CGFloat = 14
    var color: Color = CCTheme.ink4
    var majorColor: Color = CCTheme.ink3

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            ForEach(0..<count, id: \.self) { i in
                let isMajor = i % major == 0
                Rectangle()
                    .fill(.clear)
                    .frame(height: isMajor ? height : height * 0.5)
                    .frame(maxWidth: .infinity)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(isMajor ? majorColor : color)
                            .frame(width: 1)
                    }
            }
        }
        .frame(height: height, alignment: .bottom)
    }
}
