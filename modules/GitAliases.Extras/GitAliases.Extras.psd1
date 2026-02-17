@{
    RootModule = 'GitAliases.Extras.psm1'
    ModuleVersion = '0.1.0'
    GUID = 'a5c2859e-7dce-4853-9db5-8cb7927dbdda'
    Author = 'PhysShell'
    CompanyName = ''
    Copyright = ''
    Description = 'Custom git aliases and tab completion helpers for PowerShell on top of posh-git'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
        'Test-InGitRepo',
        'Test-GitInProgress',
        'Test-WorkingTreeClean',
        'Get-CurrentBranch',
        'Test-GitRefExists',
        'UpMerge',
        'UpRebase',
        'gapt',
        'gcor',
        'gdct',
        'gdt',
        'gdnolock',
        'gdv',
        'gfo',
        'glp',
        'gmtl',
        'gmtlvim',
        'gtv',
        'gtl',
        'gwip',
        'gunwip',
        'grsh',
        'gccd',
        'grl',
        'ghash',
        'gfp',
        'gsw',
        'gswc',
        'Register-GitAliasCompletion'
    )
    AliasesToExport = @(
        'gum',
        'gur',
        'gh'
    )
}
