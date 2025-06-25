// This file defines the schema for the smart contract.
// It includes data structures and serialization/deserialization logic for the contract's state.

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct ExampleSchema {
    pub id: u64,
    pub name: String,
    pub value: String,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct AnotherSchema {
    pub key: String,
    pub data: Vec<u8>,
}