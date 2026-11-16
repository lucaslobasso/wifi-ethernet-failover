@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',                       # an interactive script: errors are printed in red
        'PSUseShouldProcessForStateChangingFunctions',
        'PSUseDeclaredVarsMoreThanAssignments'         # Pester's BeforeAll/BeforeEach variables are used in the tests
    )
}
