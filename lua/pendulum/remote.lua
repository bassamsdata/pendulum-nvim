local M = {}
local chan
local bin_path
local plugin_path
local options = {}

--- Report generation setup (requires Go)
---@param opts table
function M.setup(opts)
    options.log_file = opts.log_file
    options.timer_len = opts.timer_len
    options.top_n = opts.top_n or 5

    -- Use stdpath to locate the plugin path
    plugin_path = vim.fn.stdpath("data") .. "/lazy/pendulum-nvim"
    bin_path = plugin_path .. "/remote/pendulum-nvim"

    -- Check if Go binary exists
    local uv = vim.uv or vim.loop
    ---@diagnostic disable-next-line: undefined-field
    local state = uv.fs_stat(bin_path)
    if not state then
        print("Pendulum binary not found attempting to compile with Go")
        vim.system(
            { "go", "build" },
            { cwd = plugin_path .. "/remote" },
            function(result)
                if result.code == 0 then
                    print("Go binary compiled successfully.")
                else
                    print(
                        "Failed to compile Go binary. Exit code: "
                            .. result.code
                    )
                end
            end
        )
    end
end

local function ensure_job()
    if chan then
        return chan
    end
    if not bin_path then
        print("Error: Pendulum binary not found.")
        return
    end

    chan = vim.system({ bin_path }, {
        -- Handle stdout and stderr
        stdout = function(_, data)
            if data and data ~= "" then
                print("stdout: " .. data)
            end
        end,
        stderr = function(_, data)
            if data and data ~= "" then
                print("stderr: " .. data)
            end
        end,
        on_exit = function(out)
            if out.code ~= 0 then
                print("Error: Pendulum job exited with code " .. out.code)
                chan = nil
            end
        end,
        text = true,
    })

    if not chan or chan == 0 then
        error("Failed to start pendulum-nvim job")
    end

    return chan
end

vim.api.nvim_create_user_command("Pendulum", function()
    chan = ensure_job()
    if not chan or chan == 0 then
        print("Error: Invalid channel")
        return
    end

    local args = {
        options.log_file,
        tostring(options.timer_len),
        tostring(options.top_n),
    }
    local success, result = pcall(vim.fn.rpcrequest, chan, "pendulum", args)
    if not success then
        print("RPC request failed: " .. result)
    end
end, { nargs = 0 })

vim.api.nvim_create_user_command("PendulumRebuild", function()
    print("Rebuilding Pendulum binary with Go...")
    vim.system(
        { "go", "build" },
        { cwd = plugin_path .. "/remote" },
        function(result)
            if result.code == 0 then
                print("Go binary compiled successfully.")
                if chan then
                    vim.fn.jobstop(chan)
                    chan = nil
                end
            else
                print("Failed to compile Go binary.")
            end
        end
    )
end, { nargs = 0 })

return M
