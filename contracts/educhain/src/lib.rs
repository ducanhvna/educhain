pub mod contract;
pub mod msg;
pub mod state;

#[cfg(test)]
mod tests;

use cosmwasm_std::entry_point;
use cosmwasm_std::{Deps, Env, Binary, StdResult, to_binary};
use crate::msg::QueryMsg;
use crate::state::*;

#[entry_point]
pub fn query(
    deps: Deps,
    _env: Env,
    msg: QueryMsg,
) -> StdResult<Binary> {
    match msg {
        QueryMsg::GetDid { did } => {
            let meta = DIDS.may_load(deps.storage, &did)?;
            to_binary(&meta)
        }
        QueryMsg::GetCourse { course_id } => {
            let info = COURSES.may_load(deps.storage, &course_id)?;
            to_binary(&info)
        }
        QueryMsg::GetEnrollments { course_id } => {
            let list = ENROLLMENTS.may_load(deps.storage, &course_id)?;
            to_binary(&list)
        }
        QueryMsg::HasCompleted { course_id, did } => {
            let done = COMPLETIONS.may_load(deps.storage, (course_id, did))?;
            to_binary(&done)
        }
    }
}
