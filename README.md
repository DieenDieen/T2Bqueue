# T2Bqueue
I needed a simple queue that would work fine in a multithreaded environment without too much locking. The ABA problem is avoided by a cache mechanism, which seems to be sufficient for many ordinary use cases.
