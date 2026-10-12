import Foundation

enum HomeWeatherBackground {
    static func imageName(
        at date: Date,
        sunrise: Date?,
        sunset: Date?,
        calendar: Calendar = .current
    ) -> String {
        let hour = calendar.component(.hour, from: date)
        guard let sunrise, let sunset, sunrise < sunset,
              calendar.isDate(sunrise, inSameDayAs: date),
              calendar.isDate(sunset, inSameDayAs: date)
        else {
            // shortcut: Without today's solar events, use clock hours; cache forecasts if offline precision is needed.
            switch hour {
            case 6..<12: return "WeatherMorning"
            case 12..<18: return "WeatherAfternoon"
            case 18..<20: return "WeatherEvening"
            default: return "WeatherNight"
            }
        }

        if date < sunrise.addingTimeInterval(-30 * 60) { return "WeatherNight" }
        if date < sunrise.addingTimeInterval(15 * 60) { return "WeatherSunrise" }
        if date < sunset.addingTimeInterval(-30 * 60) {
            return hour < 12 ? "WeatherMorning" : "WeatherAfternoon"
        }
        if date < sunset.addingTimeInterval(15 * 60) { return "WeatherSunset" }
        if date < sunset.addingTimeInterval(15 * 60 + 2 * 60 * 60) { return "WeatherEvening" }
        return "WeatherNight"
    }
}
