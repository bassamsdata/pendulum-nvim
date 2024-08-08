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
    uv.fs_stat(bin_path, function(stat)
        if stat then
            return
        end
        -- Compile binary if it doesn't exist
        print(
            "Pendulum binary not found at "
                .. bin_path
                .. ", attempting to compile with Go..."
        )
        vim.system(
            { "go", "build" },
            { cwd = plugin_path .. "/remote" },
            function(result)
                if result.code == 0 then
                    print("Go binary compiled successfully.")
                else
                    print("Failed to compile Go binary. " .. uv.cwd())
                end
            end
        )
    end)
end

local function ensure_job()
    if chan then
        return chan
    end
    if not bin_path then
        print("Error: Pendulum binary not found.")
        return
    end

    chan = vim.fn.jobstart({ bin_path }, {
        rpc = true,
        onexit = function(_, code, _)
            if code ~= 0 then
                print("Error: Pendulum job exited with code " .. code)
                chan = nil
            end
        end,
        onstderr = function(_, data, _)
            for _, line in ipairs(data) do
                if line ~= "" then
                    print("stderr: " .. line)
                end
            end
        end,
        onstdout = function(_, data, _)
            for _, line in ipairs(data) do
                if line ~= "" then
                    print("stdout: " .. line)
                end
            end
        end,
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
