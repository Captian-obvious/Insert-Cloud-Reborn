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
local math_min=math.min;
local math_max=math.max;
local math_random=math.random;
local math_floor=math.floor;
local math_ceil=math.ceil;
local math_abs=math.abs;
local math_exp=math.exp;
local math_log=math.log;
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
export type Worker={
    PendingWorkers:{thread},
    MaxWorkers:number,
    ActiveWorkers:number,
};
local function createWorker(workers:Worker,func,...)
    if workers.MaxWorkers==0 then return end;
    if workers.MaxWorkers>0 then -- if maxWorkers is -1, then there is no maximum
        if workers.ActiveWorkers>=workers.MaxWorkers then
            workers.PendingWorkers[#workers.PendingWorkers+1]={func,...};
            return "queued";
        end;
    end;
    local args={...};
    task_spawn(function()
        workers.ActiveWorkers=workers.ActiveWorkers+1;
        local success,err=pcall(func,table_unpack(args));
        workers.ActiveWorkers=workers.ActiveWorkers-1;
        if not success then
            warn("Worker error: "..err);
        end;
    end);
    
    return "started";
end;

function module.spawnWorker(workers:Worker,func,...)
    return createWorker(workers,func,...);
end;

function module.spawnWorkerDeferred(workers:Worker,func,...)
    return task_defer(createWorker,workers,func,...);
end;

function module.waitForWorkers(workers:Worker,timelimit) --also handles pending workers
    timelimit=timelimit or -1; --timelimit=-1 means no timelimit
    if timelimit==0 then return end;
    local start=tick();
    local passed=0;
    local timedout=false;
    local interval=0.5;
    while workers.ActiveWorkers>0 do
        if timelimit>0 then
            passed=passed+task_wait(interval);
            if passed>=timelimit then
                timedout=true;
                break;
            end;
        else
            task_wait(interval);
        end;
        if workers.ActiveWorkers<workers.MaxWorkers and next(workers.PendingWorkers) then
            local diff=workers.MaxWorkers-workers.ActiveWorkers;
            for i=1,diff do
                local new=workers.PendingWorkers[#workers.PendingWorkers];
                workers.PendingWorkers[#workers.PendingWorkers]=nil;
                if new then
                    createWorker(workers,table_unpack(new));
                end;
            end;
        end;
    end;
    return timedout;
end;

return module;
