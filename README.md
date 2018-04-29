# T2Bqueue
I needed simple queue that would work fine in multithreaded environment without too much locking. ABA problem is avoided by a cache mechanism which seems like sufficient for a many ordinary use cases.
