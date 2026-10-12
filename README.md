## Developer Mode Features

*When the developer mode toggle is on, these features will be enabled.*

- **Manual Speed Control:** Press and hold the speedometer to simulate a speed up and release to slow down.
- **Weather refresh:** Refresh the weather now (tap 5 times).

## Spotify sign-in

Spoke uses Authorization Code with PKCE and the native iOS authentication session. Users sign in from Settings; no client secret or pasted token is needed. Access and refresh tokens stay in the device Keychain, and token refresh happens automatically. The existing now-playing card and ride soundtrack history use the signed-in account. Disconnecting removes the local Spotify session.

Configure the Spotify app in the [Developer Dashboard](https://developer.spotify.com/dashboard):

- Enable Web API.
- Add the exact Redirect URI `com.beckorion.spoke.spotify://callback`.
- Set the iOS bundle ID to `com.beckorion.Spoke`.
- The public Client ID is bundled as `SpotifyClientID` in `Spoke/Info.plist`.
- In Development Mode, add each account under Users and Access. Spotify currently allows up to five users, and the app owner needs Premium. Public distribution requires Spotify’s extended quota approval.

See Spotify’s [PKCE guide](https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow), [iOS app settings](https://developer.spotify.com/documentation/web-api/concepts/apps), and [quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes).

## Ride Live Activity

Starting a ride shows elapsed riding time, distance in miles, and current speed in mph on the Lock Screen and Dynamic Island. Pause and Resume use the same saved ride session as the app, including when Spoke is in the background. Pausing freezes the timer and stops location tracking; ending the ride removes the activity. Live Activities must be enabled for Spoke in iOS Settings.

The `SpokeLiveActivity` WidgetKit extension is embedded by the Spoke target. Both targets compile the attributes and intent in `SharedLiveActivity`; only the app executes the ride action. GPS snapshots update at most every five seconds, while the system animates the elapsed timer. Speed is hidden when location is unavailable or a snapshot is stale.

Validate on a physical iPhone using the Spoke scheme’s Release Run configuration: start and lock a ride, confirm the stats update, pause and resume from both the Lock Screen and expanded Dynamic Island, then end the ride in Spoke. Also check restoring a paused ride, denying Live Activities, and large text. `RideLiveActivityTests` covers snapshot timing, persistence failures, restoration, repeated taps, stale ride buttons, and extension embedding.
