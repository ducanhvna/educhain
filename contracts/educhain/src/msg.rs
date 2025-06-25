// This file defines the messages that can be sent to the smart contract.
// It includes request and response types for contract interactions.

use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct InstantiateMsg {
    pub name: String,
    pub symbol: String,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct ExecuteMsg {
    pub transfer: Option<TransferMsg>,
    pub mint: Option<MintMsg>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct TransferMsg {
    pub recipient: String,
    pub amount: u128,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct MintMsg {
    pub recipient: String,
    pub amount: u128,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct QueryMsg {
    pub balance: Option<String>,
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq)]
pub struct BalanceResponse {
    pub balance: u128,
}