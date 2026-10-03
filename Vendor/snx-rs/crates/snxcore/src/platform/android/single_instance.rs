use std::sync::atomic::{AtomicBool, Ordering};

use crate::platform::SingleInstance;

static LOCK: AtomicBool = AtomicBool::new(false);

pub struct AndroidSingleInstance {
    held: bool,
}

impl AndroidSingleInstance {
    pub fn new<N: AsRef<str>>(_name: N) -> anyhow::Result<Self> {
        let held = LOCK
            .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
            .is_ok();
        Ok(Self { held })
    }
}

impl Drop for AndroidSingleInstance {
    fn drop(&mut self) {
        if self.held {
            LOCK.store(false, Ordering::SeqCst);
        }
    }
}

impl SingleInstance for AndroidSingleInstance {
    fn is_single(&self) -> bool {
        self.held
    }
}
