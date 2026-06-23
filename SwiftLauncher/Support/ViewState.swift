import SwiftUI

// SwiftUI 27 also exposes a State macro. Keeping the property-wrapper alias
// makes the project buildable with Command Line Tools installations that do
// not bundle the optional SwiftUIMacros plug-in.
typealias ViewState<Value> = SwiftUI.State<Value>
