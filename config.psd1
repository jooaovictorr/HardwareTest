@{
    GpuStressSeconds = 300
    CpuStressSeconds = 120
    DiskTestSizeMB   = 512

    Tools = @{
        FurMark = @{
            Id          = 'Geeks3D.FurMark.2'
            ExePaths    = @('C:\Program Files\Geeks3D\FurMark2_x64\furmark.exe')
            RequiredFor = @('GPU', 'Completo')
        }
        GPUZ = @{
            Id          = 'TechPowerUp.GPU-Z'
            ExePaths    = @(
                'C:\Program Files\GPU-Z\GPU-Z.exe'
                'C:\Program Files (x86)\GPU-Z\GPU-Z.exe'
            )
            RequiredFor = @('GPU', 'Completo')
        }
        OCCT = @{
            Id          = 'OCBase.OCCT.Personal'
            ExePaths    = @(
                'C:\Program Files\OCCT\OCCT.exe'
                'C:\Program Files (x86)\OCCT\OCCT.exe'
            )
            RequiredFor = @('Notebook', 'Completo')
        }
        CrystalDiskInfo = @{
            Id          = 'CrystalDewWorld.CrystalDiskInfo'
            ExePaths    = @(
                'C:\Program Files\CrystalDiskInfo\DiskInfo64.exe'
                'C:\Program Files (x86)\CrystalDiskInfo\DiskInfo.exe'
            )
            RequiredFor = @('Notebook', 'Completo')
        }
    }

    FurMarkPath   = 'C:\Program Files\Geeks3D\FurMark2_x64\furmark.exe'
    GpuTestWidth  = 1920
    GpuTestHeight = 1080
    ReportsSubDir = 'reports'
}
