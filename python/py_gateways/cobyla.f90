! The gateway for COBYLA
!
! Authors:
!     Tom M. RAGONNEAU (tom.ragonneau@connect.polyu.hk)
!     and Zaikun ZHANG (zaikun.zhang@polyu.edu.hk)
!     Department of Applied Mathematics,
!     The Hong Kong Polytechnic University.
!
! Dedicated to late Professor M. J. D. Powell FRS (1936--2015).

module fcobyla
use pdfoconst ! See pdfoconst.F, which defines HUGENUM
implicit none
integer :: nf
double precision, allocatable :: fhist(:),chist(:)
end module fcobyla

subroutine mcobyla (n,m,x,rhobeg,rhoend,iprint,maxfun,w,iact,f,info,funhist,conhist,ftarget,resmax,conval)
use fcobyla
implicit none
integer :: n,m,iprint,maxfun,iact(m+1),info
double precision :: x(n),rhobeg,rhoend,w(n*(3*n+2*m+11)+4*m+6),f,funhist(maxfun),conhist(maxfun),ftarget,resmax,conval(m)

nf=0
if (allocated(fhist)) deallocate (fhist)
allocate(fhist(maxfun))
if (allocated(chist)) deallocate (chist)
allocate(chist(maxfun))
fhist(:)=hugenum
chist(:)=hugenum

call cobyla (n,m,x,rhobeg,rhoend,iprint,maxfun,w,iact,f,info,ftarget,resmax,conval)

funhist=fhist
conhist=chist
deallocate(fhist)
deallocate(chist)
return
end subroutine mcobyla

subroutine calcfc (n,m,x,f,con)
use fcobyla
implicit none
integer :: n,m,i
double precision :: x(n),f,con(m),fun,confun,resmax
external :: fun,confun
f=fun(n,x)

! use extreme barrier to cope with 'hidden constraints'
if (f .gt. HUGEFUN .or. f .ne. f) then
    f = HUGEFUN ! HUGEFUN is defined in pdfoconst
endif

resmax=0.0d0
do i=1,m
    con(i)=confun(n,i,x)
    if (con(i) .lt. -HUGECON .or. con(i) .ne. con(i)) then
        con(i) = -HUGECON ! HUGECON is defined in pdfoconst
    endif

    ! This part is NOT extrem barrier. We replace extremely negative values
    ! of the constraint array (which leads to no constraint violation) by
    ! -hugecon. Otherwise, NaN of Inf may occur in the interpolation models.
    if (con(i) .gt. HUGECON) then
        con(i) = HUGECON ! HUGECON is defined in pdfoconst
    endif

    resmax=dmax1(resmax,-con(i))
enddo

nf=nf+1
fhist(nf)=f
chist(nf)=resmax
return
end subroutine calcfc
