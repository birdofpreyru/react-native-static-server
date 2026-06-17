# React Native Static Server Example

This example React Native application showcases the basic use of
[@dr.pogodin/react-native-static-server] to serve a simple static website which
is rendered inside the app using [react-native-webview] component. It also
demonstrates a few optional features relevant to such example, like messaging
between the native app and a web app inside [react-native-webview], and opening
selected web app links separately in the system browser app.

**BEWARE:** _To facilitate library development needs, this example is set up
differently from a real project &mdash; instead of consuming library code from
a node module installed from NPM, this example consumes the library from its
parent folder. Also dev setup works only with [Yarn]._

To install dependencies and run the example do in the library code base root:
`
```shell
# Installs node modules, both in the root, and in the example folder.
yarn install

# This clones and checks out the source code for PCRE2 and Lighttpd,
# which would be already packed into the library package from NPM.
git submodule update --init --recursive

# Launches the development server.
yarn example start
```

On **Android**:
  - `yarn example android` (in the library codebase root) &mdash;
    builds & deploys the example app.

On **iOS**:
  - Install pods:
    ```sh
    cd example/ios
    pod install
    ```

  - Then open, build, and run the example project in XCode.

[@dr.pogodin/react-native-static-server]: https://www.npmjs.com/package/@dr.pogodin/react-native-static-server
[react-native-webview]: https://www.npmjs.com/package/react-native-webview
[Yarn]: https://yarnpkg.com/

