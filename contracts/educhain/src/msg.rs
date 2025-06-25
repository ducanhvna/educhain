use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema)]
pub struct InstantiateMsg {}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema)]
pub enum ExecuteMsg {
    RegisterDid { did: String, metadata: String },
    CreateCourse { course_id: String, info: String },
    Enroll { course_id: String, did: String },
    CompleteCourse { course_id: String, did: String },
}

#[derive(Serialize, Deserialize, Clone, Debug, PartialEq, JsonSchema)]
pub enum QueryMsg {
    GetDid { did: String },
    GetCourse { course_id: String },
    GetEnrollments { course_id: String },
    HasCompleted { course_id: String, did: String },
}
