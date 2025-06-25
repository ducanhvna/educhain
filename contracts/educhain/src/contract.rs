use cosmwasm_std::*;
use crate::msg::{ExecuteMsg, InstantiateMsg};
use crate::state::*;

pub fn instantiate(
    deps: DepsMut,
    _env: Env,
    info: MessageInfo,
    _msg: InstantiateMsg,
) -> StdResult<Response> {
    OWNER.save(deps.storage, &info.sender)?;
    Ok(Response::new().add_attribute("method", "instantiate"))
}

pub fn execute(
    deps: DepsMut,
    _env: Env,
    _info: MessageInfo,
    msg: ExecuteMsg,
) -> StdResult<Response> {
    match msg {
        ExecuteMsg::RegisterDid { did, metadata } => {
            DIDS.save(deps.storage, &did, &metadata)?;
            Ok(Response::new().add_attribute("action", "register_did"))
        }
        ExecuteMsg::CreateCourse { course_id, info } => {
            COURSES.save(deps.storage, &course_id, &info)?;
            Ok(Response::new().add_attribute("action", "create_course"))
        }
        ExecuteMsg::Enroll { course_id, did } => {
            let mut list = ENROLLMENTS.may_load(deps.storage, &course_id)?.unwrap_or_default();
            if !list.contains(&did) {
                list.push(did.clone());
                ENROLLMENTS.save(deps.storage, &course_id, &list)?;
            }
            Ok(Response::new().add_attribute("action", "enroll"))
        }
        ExecuteMsg::CompleteCourse { course_id, did } => {
            COMPLETIONS.save(deps.storage, (course_id.clone(), did.clone()), &true)?;
            Ok(Response::new().add_attribute("action", "complete_course"))
        }
    }
}
