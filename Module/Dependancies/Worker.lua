local module = {};
local coroutine_create=coroutine.create;
local coroutine_resume=coroutine.resume;
local coroutine_status=coroutine.status;
local coroutine_running=coroutine.running;
local coroutine_wrap=coroutine.wrap;
local task_spawn=task.spawn;
local task_wait=task.wait;
local task_delay=task.delay;
local string_upper=string.upper;
local string_sub=string.sub;
local string_gsub=string.gsub;
local string_split=string.split;
local string_format=string.format;
local string_gmatch=string.gmatch;
local string_char=string.char;
local task_defer=task.defer;

local function createWorker(workers,func,...)
    local worker=coroutine.create(function(co:thread,...)
        workers[co]=true;
        func(...);
        workers[co]=nil;
    end);
    local success, err = coroutine_resume(worker,worker,...);
    if not success then
        warn(string_format("Worker error: %s", err));
    end;
    return worker;
end;

function module.spawnWorker(workers,func,...)
    return createWorker(workers,func,...);
end;

function module.spawnWorkerDeferred(workers,func,...)
    return task_defer(createWorker,workers,func,...);
end;

function module.waitForWorkers(workers,timelimit)
    timelimit=timelimit or -1; --timelimit=-1 means no timelimit
    if timelimit==0 then return end;
    local start=tick();
    local passed=0;
    local timedout=false;
    while next(workers) do
        if timelimit>0 then
            passed=passed+task_wait(.5);
            if passed>=timelimit then
                timedout=true;
                break;
            end;
        else
            task_wait();
        end;
    end;
    return timedout;
end;

return module;