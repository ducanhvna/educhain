// This file defines the state structure of the smart contract. 
// It includes the data that the contract will store and manage.

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct State {
    pub owner: String,
    pub data: Vec<u8>,
    pub timestamp: u64,
}

// Additional state-related functions can be added here.