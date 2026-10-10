import SwiftUI

/// The Help window: what everything in the meter means, in plain words. Each section wears the
/// symbol and tint the app gives that thing, and the samples are drawn with the app's own pieces
/// (chips, the ring, the orange cap title), so a reader can match them to what they see.
struct HelpView: View {
    /// False for `--render`: drawn whole rather than in a scroll view, so all of it can be checked.
    var scrolls = true

    static let width: CGFloat = 560
    private static let edge: CGFloat = 16
    private static let gap: CGFloat = 12

    var body: some View {
        if scrolls {
            ScrollView { content }
                .frame(width: Self.width, height: 640)
        } else {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Self.gap) {
            HelpHeader()
            menuBar
            fiveHour
            weekly
            accuracy
            burning
            cold
            usage
            history
            notifications
            controls
            sources
        }
        .padding(Self.edge)
        .frame(width: Self.width)
    }

    // MARK: Sections

    private var menuBar: some View {
        HelpSection(symbol: "menubar.rectangle", title: "The menu bar") {
            Sample { MenuTitleSample(text: "23% · 18m", fill: 0.23) } says: {
                Para("You've used 23% of your 5-hour limit, and it resets in 18 minutes. The ring fills up as you use more.")
            }
            Sample { MenuTitleSample(text: "~23% · 18m", fill: 0.23) } says: {
                Para("A ~ in front means the number is an estimate. No ~ means it's exact.")
            }
            Sample { MenuTitleSample(text: "31% · cap 10:49 PM", fill: 0.31, tint: Theme.warnText) } says: {
                Para("Orange with a time: at your current pace you'll hit the limit at 10:49 PM, before it resets. You get one notification when that's 30 minutes away.")
            }
            Para("The title turns orange at 70% and red at 90%. Click it to open the meter. Right-click it for the menu.",
                 secondary: true)
        }
    }

    private var fiveHour: some View {
        HelpSection(symbol: "clock", title: "5-hour window") {
            Para("Claude limits how much you can use in any 5 hours. The window starts with your first message and resets 5 hours later.")
            Bullets([
                "The big number is how much of it you've used.",
                "The chart shows how it climbed. The dashed line is where you'll end up if you keep going at this pace.",
                "The line underneath says it in words: \"At this pace: ~64% by reset\", or, in orange, the time you'd hit the limit.",
                "\"Idle\" means no window is open. Your next message starts one.",
            ])
        }
    }

    private var weekly: some View {
        HelpSection(symbol: "calendar", title: "Weekly") {
            Para("A second, bigger limit that covers 7 days. Same card, without the chart.")
            Bullets([
                "Pace: where your usual pace lands by the reset, then where today's pace would.",
                "Budget: how much you can use per day and still last until the reset, next to what you normally use. It turns orange when you're using more than that.",
                "Some weeks also show a separate limit per model, in rows underneath.",
            ])
        }
    }

    private var accuracy: some View {
        HelpSection(symbol: "scope", title: "Accuracy") {
            Sample { Chip(text: "exact · 2m ago") } says: {
                Para("Straight from Anthropic, 2 minutes ago.")
            }
            Sample { Chip(text: "est. ±1.0 · 3m ago") } says: {
                Para("An estimate. It's usually within about 1 point of the real number. The meter keeps checking its guesses against exact readings to work this out.")
            }
            Para("Hover over the label to see what the estimate is based on.", secondary: true)
        }
    }

    private var burning: some View {
        HelpSection(symbol: "flame.fill", title: "Burning now", tint: .orange) {
            Para("Every session that used Claude in the last 15 minutes, by name. If two share a name, each also says when it last ran. Hover a row for its whole name and the model it runs on.")
            BarRow(name: "Fix login bug", value: "$4.12/hr", detail: "+2.5%", fraction: 0.55)
                .padding(.vertical, 2)
            Bullets([
                "$/hr: how fast it's using your limit, shown as what the same use would cost at Anthropic's pay-as-you-go prices. Dollar amounts in the meter are a way to compare, not a bill.",
                "+2.5%: how much of your 5-hour limit it uses per hour.",
            ])
            Callout(symbol: "exclamationmark.triangle.fill", tint: .orange) {
                Para("A ⚠ means a runaway: one session used 20% or more of your 5-hour limit in 30 minutes. You also get one notification. It's usually a loop or a big job running while you're away.")
            }
        }
    }

    private var cold: some View {
        HelpSection(symbol: "snowflake", title: "Going cold", tint: .cyan) {
            Para("Claude keeps a conversation warm for about an hour after your last message. After that it goes cold, and the next message uses more of your limit, because the whole conversation has to be sent again.")
            Sample {
                HStack(spacing: 5) {
                    Chip(text: "cold in 6m", symbol: "snowflake", tint: .cyan)
                    HStack(spacing: 3) {
                        Text("then").font(Theme.meta).foregroundStyle(.secondary)
                        Text("+$1.00").font(Theme.row)
                    }
                    .monospacedDigit()
                }
                .fixedSize()
            } says: {
                Para("This session goes cold in 6 minutes. Once it has, its next message uses about $1.00 more of your limit (at pay-as-you-go prices) than it would now.")
            }
            Para("A session shows up here after 15 minutes without a message, and only if going cold would add 50¢ or more.",
                 secondary: true)
            Callout(symbol: "lightbulb.fill", tint: .accentColor) {
                Para("Still need that session? Send it something before the countdown ends.")
            }
        }
    }

    private var usage: some View {
        HelpSection(symbol: "sun.max", title: "Today / This week") {
            Bullets([
                "Today: how much you've used today, by project, in pay-as-you-go dollars.",
                "This week: each project's share of your weekly limit.",
                "In This week, \"Elsewhere\" is use the meter can't see on this Mac: claude.ai chat, the phone, other computers.",
                "The small chart shows what you used each day for the last 7 days.",
            ])
        }
    }

    private var history: some View {
        HelpSection(symbol: "chart.xyaxis.line", title: "History and plan fit") {
            Para("Click History at the bottom of the meter, or right-click the menu bar and pick History…")
            Bullets([
                "Every 5-hour window from the last 7 days, at its highest point.",
                "This week's climb, next to an even pace that would last the week.",
            ])
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 13)
                    .accessibilityHidden(true)
                Para("Plan fit: how the same use would have gone on Pro, Max 5x and Max 20x. Handy for picking a plan.")
            }
        }
    }

    private var notifications: some View {
        HelpSection(symbol: "bell", title: "Notifications") {
            Bullets([
                "At 80% and 95% of each limit, once each.",
                "When a 5-hour window that went past 80% resets, so you know you're clear.",
                "When you're 30 minutes from hitting the 5-hour limit.",
                "When a session runs away (see Burning now).",
            ])
            Para("\"Send test notification\" checks they get through. If macOS is blocking them, it opens the settings to fix it.",
                 secondary: true)
        }
    }

    private var controls: some View {
        HelpSection(symbol: "gearshape", title: "Sync, the shortcut and settings") {
            Sample { Chip(text: "Sync", symbol: "arrow.clockwise") } says: {
                Para("Gets an exact reading right now. It never starts a new 5-hour window: if none is open, it tells you instead.")
            }
            Sample { KeyCaps(keys: ["⌃", "⌥", "⌘", "U"]) } says: {
                Para("Control-Option-Command-U opens the meter from anywhere.")
            }
            Para("The gear button, or a right-click on the menu bar, has the settings:")
            VStack(alignment: .leading, spacing: 3) {
                SettingRow(symbol: "arrow.up.forward.app", name: "Open at login", text: "starts the meter when you log in.")
                SettingRow(symbol: "calendar", name: "Weekly % in menu bar", text: "adds the weekly number to the title.")
                SettingRow(symbol: "bell", name: "Notifications", text: "turns all alerts on or off.")
                SettingRow(symbol: "bell.badge", name: "Send test notification", text: "sends one now.")
                SettingRow(symbol: "command", name: "Shortcut ⌃⌥⌘U", text: "turns the shortcut on or off.")
            }
        }
    }

    private var sources: some View {
        HelpSection(symbol: "dot.radiowaves.left.and.right", title: "Where the numbers come from") {
            Bullets([
                "Exact readings come from Anthropic, about once a minute while you're working, and never while you're idle. Each uses a tiny sliver of your limit.",
                "In between, the meter estimates from Claude Code's own records on this Mac.",
                "It can't see claude.ai chat, the phone app or your other computers. The next exact reading catches up, and until then the meter leans toward showing a bit too much rather than too little.",
            ])
            Callout(symbol: "exclamationmark.triangle.fill", tint: .orange) {
                Para("If the line at the bottom of the meter turns orange, it can't get exact readings. Usually Claude Code is signed out: open Terminal, type claude, then /login.")
            }
        }
    }
}

// MARK: Building blocks

/// The window's opening: the meter's ring as an icon, and what the app is for.
private struct HelpHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                Ring(fill: 0.62, tint: .accentColor, line: 4)
                    .frame(width: 24, height: 24)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("How Claude Meter works")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                Text("It shows how much of your Claude plan you've used, so a limit never takes you by surprise.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }
}

/// A module with the section's symbol and tint in its title.
private struct HelpSection<Content: View>: View {
    let symbol: String
    let title: String
    var tint: Color = .secondary
    @ViewBuilder var content: Content

    var body: some View {
        Module {
            ModuleTitle(symbol: symbol, title: title, tint: tint)
                .padding(.bottom, 2)
            VStack(alignment: .leading, spacing: 7) { content }
        }
    }
}

/// A paragraph that wraps rather than truncates.
private struct Para: View {
    let text: String
    var secondary = false

    init(_ text: String, secondary: Bool = false) {
        self.text = text
        self.secondary = secondary
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .lineSpacing(2)
            .foregroundStyle(secondary ? Color.secondary : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Short points with a quiet dot ahead of each.
private struct Bullets: View {
    let items: [String]

    init(_ items: [String]) { self.items = items }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Circle().fill(Theme.quiet).frame(width: 4, height: 4)
                        .alignmentGuide(.firstTextBaseline) { $0[.bottom] + 1 }
                        .frame(width: 8)
                        .accessibilityHidden(true)
                    Para(item)
                }
            }
        }
    }
}

/// What the reader will see on the left, what it means on the right.
private struct Sample<Shown: View, Meaning: View>: View {
    @ViewBuilder var shown: Shown
    @ViewBuilder var says: Meaning

    static var column: CGFloat { 150 }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            shown
                .frame(width: Self.column, alignment: .leading)
                .padding(.top, 1)
            says
        }
    }
}

/// A tinted note: a tip or a warning.
private struct Callout<Content: View>: View {
    let symbol: String
    let tint: Color
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.text(tint))
                .frame(width: 14)
                .accessibilityHidden(true)
            content
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.11)))
    }
}

/// The menu bar title as it appears there: the ring, then the text.
private struct MenuTitleSample: View {
    let text: String
    let fill: Double
    var tint: Color = .primary

    var body: some View {
        HStack(spacing: 4) {
            Ring(fill: fill, tint: tint, line: 2)
                .frame(width: 11, height: 11)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.track))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// A ring filled clockwise from the top, like the menu bar's.
private struct Ring: View {
    let fill: Double
    let tint: Color
    let line: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: line)
            Circle().trim(from: 0, to: fill)
                .stroke(tint, style: StrokeStyle(lineWidth: line, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(line / 2)
    }
}

/// Keyboard keys, each in its own cap.
private struct KeyCaps: View {
    let keys: [String]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 11, weight: .medium))
                    .frame(minWidth: 20, minHeight: 19)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Theme.track))
                    .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Theme.hairline, lineWidth: 0.5))
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Control Option Command U")
    }
}

/// A setting from the menu: its symbol, its name, and what it does.
private struct SettingRow: View {
    let symbol: String
    let name: String
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 14)
                .accessibilityHidden(true)
            (Text(name).fontWeight(.medium) + Text("  ") + Text(text).foregroundStyle(.secondary))
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
