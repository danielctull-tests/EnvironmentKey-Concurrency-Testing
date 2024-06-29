# EnvironmentKey Concurrency Testing

This package shows a common use case of creating a SwiftUI container view and style pair. And shows how I resolved the issues that arose from turning on strict concurrency checking.

### Enable Strict Concurrency Checking

My first step was to [enable strict concurrency](https://github.com/danielctull-tests/EnvironmentKey-Concurrency-Testing/compare/enable-strict-concurrency) checking. I did this at the package level, but this can also be done at the target level.

### Annotating `DetailStyle` with @MainActor

```swift
extension DetailStyle {

    fileprivate func resolve(configuration: Configuration) -> some View {
        ResolvedDetailStyle(style: self, configuration: configuration)
    }
}

private struct ResolvedDetailStyle<Style: DetailStyle>: View {

    let style: Style
    let configuration: Style.Configuration

    var body: some View {
        style.makeBody(configuration: configuration)
    }
}
```

A few warnings appear with a couple in the `DetailStyle.resolve(configuration)` function about calling the main actor isolated initialiser for `ResolvedDetailStyle` and another about sending `self` to said initialiser.

> Call to main actor-isolated initializer 'init(style:configuration:)' in a synchronous nonisolated context; this is an error in the Swift 6 language mode

> Sending 'self' risks causing data races; this is an error in the Swift 6 language mode

The solution here is to mark `DetailStyle` as being isolated to the main actor so that it can create a the view, which is now on the main actor in iOS 18.

```swift
@MainActor
public protocol DetailStyle: DynamicProperty {

    typealias Configuration = DetailStyleConfiguration
    associatedtype Body: View

    @ViewBuilder func makeBody(configuration: Configuration) -> Body
}
```

Looking at Apple’s documentation for [`LabelStyle`](https://developer.apple.com/documentation/swiftui/labelstyle?changes=latest_major) and [`ButtonStyle`](https://developer.apple.com/documentation/swiftui/buttonstyle?changes=latest_major) show that Apple also made the same change to make those main actor isolated types in Xcode 16.

### Annotating `DetailStyleConfiguration` with @MainActor

A few warnings appear, with a cluster being related to initialising the `Primary`, `Secondary` and `Tertiary` wrapper views from a nonisolated context in `DetailStyleConfiguration`.

> Call to main actor-isolated initializer 'init(base:)' in a synchronous nonisolated context; this is an error in the Swift 6 language mode

> Sending task-isolated value of type 'AnyView' with later accesses to main actor-isolated context risks causing data races; this is an error in the Swift 6 language mode

Again, because `DetailStyleConfiguration` is created from the body of the `Detail` view and is used in the (now main actor isolated) `DetailStyle.makeBody(configuration:)` function, it makes sense for this type to also be tied to the main actor.

### Detail Style Environment Key

```swift
private enum DetailStyleKey: EnvironmentKey {
    static var defaultValue: any DetailStyle = DefaultDetailStyle()
}
```

An initial warning appears for the `defaultValue` static property.

> Static property 'defaultValue' is not concurrency-safe because it is non-isolated global shared mutable state; this is an error in the Swift 6 language mode

To resolve this warning, we change from using a `var` to a `let`. As this value is never set, this should always have been the case, but Xcode’s autocomplete always put `var` and this snuck in.

```swift
private enum DetailStyleKey: EnvironmentKey {
    static let defaultValue: any DetailStyle = DefaultDetailStyle()
}
```

Fixing this provides a second warning:

> Static property 'defaultValue' is not concurrency-safe because non-'Sendable' type 'any DetailStyle' may have shared mutable state; this is an error in the Swift 6 language mode

Here, `any DetailStyle` isn’t marked as sendable, so the compiler cannot guarantee that the internals won’t mutate. This could happen if the conforming type were a class, had a class property or had a non-sendable closure property.

One solution here is to ensure all types conforming to `DetailStyle` also conform to `Sendable` by adding the conformance to `DetailStyle`. This ensures that conforming types must be allowed to cross isolation boundaries.

```swift
public protocol DetailStyle: DynamicProperty, Sendable
```

However, I noticed that Apple haven’t done this (yet?) with `LabelStyle` and `ButtonStyle`.

Another way to fix it is to mark the `defaultValue` property as being on the main actor. This makes sense to me, as it’s only there to be read from view bodies.

```swift
private enum DetailStyleKey: EnvironmentKey {
    @MainActor static let defaultValue: any DetailStyle = DefaultDetailStyle()
}
```

However, in doing so, we get another warning:

> Main actor-isolated static property 'defaultValue' cannot be used to satisfy nonisolated protocol requirement; this is an error in the Swift 6 language mode

`EnvironmentKey` is nonisolated and so this main actor isolated property doesn’t satisfy the requirement. To put it another way, if the system called `defaultValue` from another actor, which would be fine for it to do, it would have to jump to the main actor, causing a suspension point. But the protocol doesn’t say a suspension is needed…

```swift
private enum DetailStyleKey: @preconcurrency EnvironmentKey {
    @MainActor static let defaultValue: any DetailStyle = DefaultDetailStyle()
}
```

