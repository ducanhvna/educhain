use cosmwasm_std::Addr;
use cw_storage_plus::{Item, Map};

pub const OWNER: Item<Addr> = Item::new("owner");
pub const DIDS: Map<String, String> = Map::new("dids");
pub const COURSES: Map<String, String> = Map::new("courses");
pub const ENROLLMENTS: Map<String, Vec<String>> = Map::new("enrollments");
pub const COMPLETIONS: Map<(String, String), bool> = Map::new("completions");
