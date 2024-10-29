# PerfScale UI Query

## Prerequisite:
- Install [Chainsaw](https://kyverno.github.io/chainsaw/0.2.3/)
- Add infra node to your cluster
- Install Tempo Operator (OCP console -> Operators -> OperatorHub)
- Install Red Hat build of OpenTelemetry operator


## Run test

```bash
chainsaw test
```

The same but not delete resources after test

```bash
chainsaw test --skip-delete
```
