use secrecy::SecretString;
use uuid::Uuid;

use crate::platform::Keychain;

#[derive(Default)]
pub struct AndroidKeychain;

impl AndroidKeychain {
    pub fn new() -> Self {
        Self
    }
}

impl Keychain for AndroidKeychain {
    async fn acquire_password(&self, _profile_id: Uuid) -> anyhow::Result<String> {
        anyhow::bail!("Android keychain is owned by the Kotlin app")
    }

    async fn store_password(&self, _profile_id: Uuid, _password: &SecretString) -> anyhow::Result<()> {
        Ok(())
    }

    async fn delete_password(&self, _profile_id: Uuid) -> anyhow::Result<()> {
        Ok(())
    }
}
