Run the scheduler and price snapshot cache regression checks from the project root:

```sh
swiftc -parse-as-library PriceParity/PricePointLoader.swift PriceParity/PriceSnapshotCache.swift Tests/PricePointLoaderTests.swift -o /tmp/PricePointLoaderTests
/tmp/PricePointLoaderTests
```

These use simulated requests and temporary cache files; they do not access App Store Connect or modify prices.
