--!optimize 2

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
local table_insert=table.insert;
local table_pack=table.pack;
local table_move=table.move;
local table_remove=table.remove;
local table_concat=table.concat;
local table_find=table.find;
local table_sort=table.sort;
local table_unpack=table.unpack;
local function createWorker(workers,func,...)
    local args={...};
    local worker=coroutine_create(function(...)
        local co=coroutine_running();
        workers[co]=true;
        local suc,err=pcall(func,...);
        if not suc then
            warn(string_format("Worker error: %s", err));
        end;
        workers[co]=nil;
    end);
    local ok, err = coroutine_resume(worker,table_unpack(args));
    if not ok then
        warn(string_format("Worker error: %s", err));
        if workers[worker] then
            workers[worker]=nil;
        end;
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
    local interval=0.5;
    while next(workers) do
        if timelimit>0 then
            passed=passed+task_wait(interval);
            if passed>=timelimit then
                timedout=true;
                break;
            end;
        else
            task_wait(interval);
        end;
    end;
    return timedout;
end;

return module;
