import WidgetKit
import SwiftUI

struct StudyEntry: TimelineEntry {
    let date: Date
    let streak: Int
    let readiness: Int
    let sessionsToday: Int
}

struct StudyWidgetProvider: TimelineProvider {
    let groupId = "group.com.niotron.domingotambasacan.pnleaireviewer2026"

    func placeholder(in context: Context) -> StudyEntry {
        StudyEntry(date: Date(), streak: 0, readiness: 0, sessionsToday: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (StudyEntry) -> ()) {
        let entry = loadEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StudyEntry>) -> ()) {
        let entry = loadEntry()
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> StudyEntry {
        let prefs = UserDefaults(suiteName: groupId)
        let streak = prefs?.integer(forKey: "study_streak") ?? 0
        let readiness = prefs?.integer(forKey: "readiness_score") ?? 0
        let sessionsToday = prefs?.integer(forKey: "sessions_today") ?? 0
        return StudyEntry(date: Date(), streak: streak, readiness: readiness, sessionsToday: sessionsToday)
    }
}

struct StudyWidgetEntryView: View {
    var entry: StudyWidgetProvider.Entry

    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:
            smallWidget
        default:
            mediumWidget
        }
    }

    var smallWidget: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
                Text("\(entry.streak)")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            Text("Day Streak")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            HStack {
                VStack {
                    Text("\(entry.readiness)%")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(readinessColor)
                    Text("Ready")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                VStack {
                    Text("\(entry.sessionsToday)/4")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text("Today")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
    }

    var mediumWidget: some View {
        HStack(spacing: 16) {
            // Streak
            VStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundColor(.orange)
                    .font(.title)
                Text("\(entry.streak)")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Day Streak")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Readiness
            VStack(spacing: 4) {
                Text("\(entry.readiness)%")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(readinessColor)
                Text("Readiness")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)

            Divider()

            // Sessions
            VStack(spacing: 4) {
                Text("\(entry.sessionsToday)/4")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.blue)
                Text("Sessions")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
    }

    var readinessColor: Color {
        if entry.readiness >= 75 { return .green }
        if entry.readiness >= 50 { return .orange }
        return .red
    }
}

struct StudyWidget: Widget {
    let kind: String = "StudyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StudyWidgetProvider()) { entry in
            if #available(iOS 17.0, *) {
                StudyWidgetEntryView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                StudyWidgetEntryView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("PNLE Study Tracker")
        .description("Track your study streak, readiness score, and daily sessions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
