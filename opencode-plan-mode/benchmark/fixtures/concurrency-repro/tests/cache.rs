use std::sync::Arc;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::time::Duration;
use concurrency_repro::{Cache, Value};

#[tokio::test(flavor = "multi_thread", worker_threads = 8)]
async fn compute_runs_exactly_once() {
    let cache = Cache::new();
    let calls = Arc::new(AtomicUsize::new(0));
    let barrier = Arc::new(tokio::sync::Barrier::new(50));
    let mut handles = Vec::new();
    for _ in 0..50 {
        let cache = cache.clone();
        let calls = Arc::clone(&calls);
        let barrier = Arc::clone(&barrier);
        handles.push(tokio::spawn(async move {
            barrier.wait().await;
            cache
                .get_or_insert("k", Duration::from_secs(60), || {
                    calls.fetch_add(1, Ordering::SeqCst);
                    Value("v".to_string())
                })
                .await;
        }));
    }
    for h in handles {
        h.await.unwrap();
    }
    assert_eq!(calls.load(Ordering::SeqCst), 1);
}
