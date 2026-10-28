import SwiftUI

/// The Help window: what everything in the meter means, in plain words. Each section wears the
/// symbol and tint the app gives that thing, and the samples are drawn with the app's own pieces
/// (chips, the ring, the orange cap title), so a reader can match them to what they see.
struct HelpView: View {
    /// False for `--render`: drawn whole rather than in a scroll view, so all of it can be checked.
    var scrolls = true

    static let width: CGFloat = 560
    /// How tall the window first opens; it scrolls the rest and can be dragged taller.
    static let height: CGFloat = 640
    private static let edge: CGFloat = 16
    private static let gap: CGFloat = 12

    var body: some View {
        if scrolls {
            ScrollView { content }
                .frame(width: Self.width)
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
            fable
            usageCredits
            credits
            accuracy
            burning
            cold
            usage
            history
            value
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
            Sample { MenuTitleSample(text: "31% · cap 10:49", fill: 0.31, tint: Theme.warnText) } says: {
                Para("Orange with a time: at your current pace you'll hit the limit at 10:49, before it resets. You get one notification when that's 30 minutes away.")
            }
            Sample { MenuTitleSample(text: "2h50m wk 41%", fill: 0.23) } says: {
                Para("With Weekly % in menu bar on: the ring is your 5-hour %, then the time to reset and your weekly %.")
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
                "\"Worth $540 so far · 11.7× your plan\" is what this week's use would have cost at pay-as-you-go prices, and how many times what your plan costs for a week that is. A \"~\" before the amount means part of it is an estimate (Other, see Value this week). Click History on that line for the details.",
            ])
        }
    }

    private var fable: some View {
        HelpSection(symbol: FableCard.symbol, title: "Fable", tint: Theme.fable) {
            Para("Max plans have a separate weekly limit just for Fable, Anthropic's most capable model. This card is that limit: how much of it you've used, when it resets, and how fresh the reading is. It only climbs when you use Fable, on any device.")
            Bullets([
                "The number and the bar are the Fable limit itself, straight from Anthropic. Pink is Fable's colour. It still turns orange at 70% and red at 90%.",
                "\"This Mac: ~3% of the 5-hour window · ~1% of the week ($2.20)\" is Fable's part of your overall limits, worked out from this Mac's Claude Code records: how much of the 5-hour window and of the week went to Fable, and what that use would cost at pay-as-you-go prices.",
                "In Burning now, a session running on Fable has a pink bar.",
            ])
            Para("The reading comes from Claude Code's own usage report (the same numbers as typing /usage): every 5 minutes while Fable is in use on this Mac or no 5-hour window is open (that is how a window opened on another device is noticed), every 30 otherwise, and on Sync. It costs nothing and never starts a 5-hour window. The Fable limit doesn't send notifications.",
                 secondary: true)
            Para("If your plan has no separate Fable limit, the card says so, and Fable simply counts toward the 5-hour and weekly limits above. The card appears once Fable has been used this week.",
                 secondary: true)
        }
    }

    private var usageCredits: some View {
        HelpSection(symbol: "dollarsign.circle", title: "Usage credits") {
            Para("Extra usage on your Claude plan (claude.ai › Settings › Usage): once you hit a limit, extra usage keeps you going and is paid from usage credits, up to a monthly limit you set. The card, on the dropdown's Credits tab, shows this month's extra usage against that limit, and your prepaid balance. It appears once extra usage has ever been turned on.")
            Bullets([
                "\"$12.40 of $40.00 this month\" is extra usage spent this month against your monthly limit; \"balance\" is the prepaid credits left.",
                "Red when the monthly limit is reached: extra usage is off until it resets or you raise the limit on claude.ai.",
            ])
            Para("Read the way Claude Code's /usage reads it, with Claude Code's sign-in on this Mac, every 15 minutes. Nothing to set up.", secondary: true)
        }
    }

    private var credits: some View {
        HelpSection(symbol: "creditcard", title: "API credits") {
            Para("The prepaid credits in your Anthropic Console (platform.claude.com) that pay for API calls made with an API key, such as a tool's own research runs. They are separate from your plan's limits above. The card is on the dropdown's Credits tab once you type a balance in: Set up on that tab, API credits… in the gear menu, or a right-click on the menu bar. While a card on Credits shows a red line, the tab has a red dot.")
            Bullets([
                "Typed in: copy the total left from the Console's Billing page, and optionally the grant's size and the day it expires. Anthropic has no way for an app to read the balance itself, so this number is the starting point.",
                "Console: with a Console key in your keychain, the meter reads Anthropic's cost report every 15 minutes (real billed spend, about 5 minutes behind) and takes it off the balance you typed. The line under it is the pace over the last 7 days.",
                "Red only when, at that pace, the credits run out before they expire, or are used up.",
                "When a new month's credits land, press Update and type the new total; the meter can't see them arrive. After the expiry day the card goes gray until you do. With more than one grant, type the soonest expiry, or update the balance after it.",
            ])
            Para("To add the key, open Terminal and run this, then paste the key when it asks (it never lands in your shell history):", secondary: true)
            Text("security add-generic-password -U -s \"\(ConsoleCredits.keychainService)\" -a console -w")
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Para("The cost report needs a key that can read your organization's costs: an Admin API key (made by an admin in the Console's settings), or a personal key not tied to a workspace (Create key with Scope: Organization). Either works only once your Console account is set up as an organization (Console › Settings › Organization; free). An Admin key can also create keys and manage members, so keep it to this one keychain item. The key is read for each check and kept nowhere else. The day you type a balance in counts from that moment if a key is there; without one, spend counts from the next day (UTC).",
                 secondary: true)
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
            Para("Every session that used Claude in the last 15 minutes at 50¢ an hour or more (at pay-as-you-go prices), by name. A runaway stays here with its ⚠ for 30 minutes, even once it has gone quiet. Two different sessions can share a name (two threads in one folder). Then each also says when it started, here and in Going cold, so you can tell them apart. Hover a row for its whole name and the model it runs on.")
            Sample {
                HStack(spacing: 4) {
                    ForEach(Array([ModelFamily.opus, .sonnet, .haiku, .fable].enumerated()), id: \.offset) { _, f in
                        Mascot(pose: .run, color: f.full)
                    }
                    Mascot(pose: .asleep, color: ModelFamily.opus.muted)
                }
            } says: {
                Para("Each session has a mascot in its model's colour: purple Opus, orange Sonnet, teal Haiku, pink Fable. A bobbing mascot is working (Burning now, and the crew at the top of the dropdown). Eyes shut in a dimmer colour means idle and going cold. The still ones on the limit cards just label them.")
            }
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
                HStack(spacing: 4) {
                    Chip(text: "cold in 6m", tint: .cyan)
                    Text("then").font(Theme.row).foregroundStyle(.secondary)
                    Text("+$1.00").font(Theme.row).monospacedDigit()
                }
                .fixedSize()
            } says: {
                Para("This session goes cold in 6 minutes. Once it has, its next message uses about $1.00 more of your limit (at pay-as-you-go prices) than it would now.")
            }
            Para("A session shows up here after 15 minutes without a message, and only if going cold would add 50¢ or more. A session on the short 5-minute cache is already cold by then, so it never shows up.",
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
                "This week: each project's share of your weekly limit, and each cloud session (\"Cloud: …\", gray bar) by its title: claude.ai/code sessions and project threads, from the sessions list.",
                "In This week, \"Other\" is use neither this Mac nor the sessions list accounts for: claude.ai chat, the phone, other computers.",
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

    private var value: some View {
        HelpSection(symbol: WeekValueSection.symbol, title: "Value this week") {
            Para("The first thing in History: what your use since the weekly limit last reset would have cost if you paid Anthropic's pay-as-you-go prices instead of a plan.")
            Bullets([
                "The big number is the total. The one next to it is how many times what your plan costs for a week that is: $20, $100 or $200 a month (Pro, Max 5x, Max 20x, from the plan picker in Plan fit), spread over 52 weeks.",
                "The bar splits it in three. This Mac's Claude Code (dark gray), counted from its records. Cloud sessions (mid gray): claude.ai/code sessions and project threads, exact, from the sessions list Anthropic keeps, read every 5 minutes with the Claude Code sign-in on this Mac. Other (light gray): claude.ai chat, the phone and other computers, worked out from your weekly %. The blue tick is your plan's week.",
                "The first time, macOS may ask once to let Claude Meter read Claude Code's sign-in from the keychain. It's only held in memory and only sent to Anthropic. Remote Control sessions run on this Mac aren't counted twice: their records here already are. Turn it off with Cloud sessions in the settings.",
                "A \"~\" before the total means it includes Other, so part of it is an estimate. With no Other, there's no \"~\".",
                "The columns are each day of the week so far, this Mac with the cloud stacked on top (Other can't be split by day). A reset in the afternoon makes the first and last days partial, so the reset's weekday shows twice. Today's label is bold.",
                "Underneath, this Mac's part by model.",
            ])
        }
    }

    private var notifications: some View {
        HelpSection(symbol: "bell", title: "Notifications") {
            Bullets([
                "At 80% and 95% of the 5-hour and weekly limits, once each. Per-model weekly rows and the Fable limit don't alert.",
                "When a 5-hour window that went past 80% resets, so you know you're clear.",
                "When you're 30 minutes from hitting the 5-hour limit.",
                "When a session runs away (see Burning now).",
                "When exact readings stop: an hour of using Claude Code without one, so everything shown is an estimate. Usually a Claude Code update or a sign-out; try Sync.",
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
                SettingRow(symbol: "calendar", name: "Weekly % in menu bar", text: "adds the weekly % to the title; the ring then shows the 5-hour %.")
                SettingRow(symbol: "cloud", name: "Cloud sessions", text: "reads Anthropic's list of your cloud sessions and what each cost (on unless you turn it off).")
                SettingRow(symbol: "bell", name: "Notifications", text: "turns all alerts on or off.")
                SettingRow(symbol: "bell.badge", name: "Send test notification", text: "sends one now.")
                SettingRow(symbol: "command", name: "Shortcut ⌃⌥⌘U", text: "turns the shortcut on or off.")
                SettingRow(symbol: "creditcard", name: "API credits…", text: "types in your Console credit balance (see API credits).")
            }
        }
    }

    private var sources: some View {
        HelpSection(symbol: "dot.radiowaves.left.and.right", title: "Where the numbers come from") {
            Bullets([
                "Exact readings come from Anthropic, once a minute while a 5-hour window is open, so use on other devices shows up too. None while no window is open, since asking would start one. A window opened on another device is noticed within about 5 minutes. Each uses a tiny sliver of your limit.",
                "In between, the meter estimates from Claude Code's own records on this Mac, and from what your cloud sessions cost (Anthropic's sessions list, read every 5 minutes).",
                "The Fable limit comes from Claude Code's usage report, which costs nothing to read.",
                "It can't see claude.ai chat, the phone app or your other computers. The next exact reading catches up, and until then the meter leans toward showing a bit too much rather than too little.",
                "Cloud sessions are counted from what each session cost. A session already running when the meter first saw it is spread evenly over its life, so only its share since the week began counts toward this week.",
            ])
            Callout(symbol: "exclamationmark.triangle.fill", tint: .orange) {
                Para("If the line at the bottom of the meter turns orange, it can't get exact readings. Usually Claude Code is signed out: open Terminal, type claude, then /login. While it is, a card with no recent reading shows — and \"Signed out, so no reading\" rather than a guess.")
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
