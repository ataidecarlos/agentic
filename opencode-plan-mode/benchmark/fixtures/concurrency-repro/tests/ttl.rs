use std::time::Duration;
use concurrency_repro::{Cache, Value};

#[tokio::test(flavor = "multi_thread", worker_threads = 8)]
async fn stale_insert_does_not_clobber_fresher_entry() {
    let cache = Cache::new();
    let slow = tokio::spawn({
        let cache = cache.clone();
        async move {
            // Miss path with a deliberately slow compute.
            cache
                .get_or_insert("k", Duration::from_millis(30), || {
                    std::thread::sleep(Duration::from_millis(50));
                    Value("stale".to_string())
                })
                .await
        }
    });
    tokio::time::sleep(Duration::from_millis(5)).await;
    // Quick refresh while `slow` is still computing.
    cache
        .get_or_insert("k", Duration::from_secs(60), || Value("fresh".to_string()))
        .await;
    slow.await.unwrap();
    // `slow` finished last but its miss-path entry (TTL 30ms) overwrote the
    // fresh one. The cache must still serve "fresh".
    let served = cache
        .get_or_insert("k", Duration::from_secs(60), || Value("unreachable".to_string()))
        .await;
    assert_eq!(served.0, "fresh");
}
