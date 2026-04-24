# SDK Demo

`samples/sdk_demo` is the Phase 4 tooling ecosystem proof workspace. It demonstrates build, test, format, check, package, local registry publish/search/install, and a consumer executable.

```bash
./build/hy build samples/sdk_demo/SdkDemo.hyproj
./build/hy test samples/sdk_demo/SdkDemo.hyproj
./build/hy fmt --check samples/sdk_demo
./build/hy check samples/sdk_demo/SdkDemo.hyproj --json
./build/hy package init-registry build/local-registry
./build/hy package publish samples/sdk_demo/SdkDemo.Core/SdkDemo.Core.hyproj --registry build/local-registry
./build/hy package search SdkDemo --registry build/local-registry
./build/hy package install samples/sdk_demo/SdkDemo.Consumer/SdkDemo.Consumer.hyproj SdkDemo.Core --registry build/local-registry
./build/hy run samples/sdk_demo/SdkDemo.Consumer/SdkDemo.Consumer.hyproj
```
