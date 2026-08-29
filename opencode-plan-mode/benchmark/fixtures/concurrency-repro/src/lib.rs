use std::collections::HashMap;
use std::sync::Arc;
use std::time::{Duration, Instant};
use tokio::sync::Mutex;

#[derive(Clone)]
pub struct Value(pub String);

#[derive(Clone)]
struct Entry {
    value: Arc<Value>,
    expires_at: Instant,
}

#[derive(Clone)]
pub struct Cache {
    map: Arc<Mutex<HashMap<String, Entry>>>,
}

impl Cache {
    pub fn new() -> Self {
        Self { map: Arc::new(Mutex::new(HashMap::new())) }
    }

    // BUG (check-then-act): the validity check and compute+insert are not one
    // atomic critical section. The lock is dropped after the snapshot, so (1)
    // concurrent callers that all observe a miss each run `compute`, and (2) a
    // slow miss-path insert can overwrite a fresher entry inserted meanwhile.
    pub async fn get_or_insert<F>(&self, key: &str, ttl: Duration, compute: F) -> Arc<Value>
    where
        F: FnOnce() -> Value,
    {
        let cached = {
            let guard = self.map.lock().await;
            guard.get(key).cloned()
        };
        if let Some(entry) = cached {
            if entry.expires_at > Instant::now() {
                return entry.value;
            }
        }
        let value = Arc::new(compute());
        let entry = Entry {
            value: value.clone(),
            expires_at: Instant::now() + ttl,
        };
        self.map.lock().await.insert(key.to_string(), entry);
        value
    }
}
