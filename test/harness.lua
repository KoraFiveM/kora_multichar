local Harness = { passed = 0, failed = 0 }

function Harness.test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        Harness.passed = Harness.passed + 1
        print(('  PASS  %s'):format(name))
    else
        Harness.failed = Harness.failed + 1
        print(('  FAIL  %s\n        %s'):format(name, tostring(err)))
    end
end

function Harness.equal(actual, expected, message)
    if actual ~= expected then error(('%s (expected %s, got %s)'):format(message or 'values differ', tostring(expected), tostring(actual)), 2) end
end

function Harness.truthy(value, message)
    if not value then error(message or 'expected a truthy value', 2) end
end

function Harness.falsy(value, message)
    if value then error(message or 'expected a falsy value', 2) end
end

function Harness.close(actual, expected, epsilon, message)
    if math.abs(actual - expected) > (epsilon or 0.0001) then
        error(('%s (expected %.6f, got %.6f)'):format(message or 'values are not close', expected, actual), 2)
    end
end

function Harness.report(label)
    print(('  %s: %d passed, %d failed'):format(label, Harness.passed, Harness.failed))
    if Harness.failed > 0 then os.exit(1) end
end

return Harness
