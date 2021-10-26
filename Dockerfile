FROM databricksruntime/minimal:9.x

ARG ESMF_TAG="ESMF_8_0_0_beta_snapshot_40"
ARG NETCDF_PREFIX=/usr

# Installs python 3.8 and virtualenv for Spark and Notebooks
RUN apt-get update \
  && apt-get install -y \
    python3.8 \
    python3.8-dev \
    python3.8-distutils \
    build-essential \
    virtualenv \
    python3-eccodes \
    libproj-dev \
    proj-data \
    proj-bin \
    libgeos-dev \
    git vim wget bc gcc gfortran g++ mpich \
    libnetcdf-dev libnetcdff-dev netcdf-bin \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Initialize the default environment that Spark and notebooks will use
RUN virtualenv -p python3.8 /databricks/python3

# Get ESMF source code
WORKDIR /opt/esmf_build
RUN git archive --remote=git://git.code.sf.net/p/esmf/esmf --format=tar --prefix=esmf_source/ $ESMF_TAG | tar xf -
WORKDIR /opt/esmf_build/esmf_source

# set environment variables for ESMF
ENV ESMF_DIR=/opt/esmf_build/esmf_source
ENV ESMF_INSTALL_PREFIX=/opt/esmf_build/esmf_install
ENV ESMF_NETCDF="split"
ENV ESMF_NETCDF_INCLUDE=$NETCDF_PREFIX/include
ENV ESMF_NETCDF_LIBPATH=$NETCDF_PREFIX/lib
ENV ESMF_COMM=mpich3
ENV ESMF_COMPILER=gfortran

# build ESMF
RUN make info 2>&1 | tee esmf-make-info.out
RUN make 2>&1 | tee esmf-make.out
#RUN make check 2>&1 | tee esmf-make-check.out
RUN make install 2>&1 | tee esmf-make-install.out

# build ESMPy and install all required python librairies
# These python libraries are used by Databricks notebooks and the Python REPL
# You do not need to install pyspark - it is injected when the cluster is launched
# Versions are intended to reflect DBR 9.0
WORKDIR $ESMF_DIR/src/addon/ESMPy
ENV VIRTUAL_ENV=/databricks/python3
ENV PATH="$VIRTUAL_ENV/bin:$PATH"
RUN ESMFMKFILE="$(find $ESMF_INSTALL_PREFIX -name '*esmf.mk')" \
    && echo "ESMFMKFILE=$ESMFMKFILE" \
    && . /databricks/python3/bin/activate \
    && /databricks/python3/bin/pip install numpy nose --ignore-installed \
    && /databricks/python3/bin/python3 setup.py build --ESMFMKFILE=${ESMFMKFILE} \
    && /databricks/python3/bin/python3 setup.py test \
    && /databricks/python3/bin/python3 setup.py install \
    && /databricks/python3/bin/python3 -c "import ESMF; print(ESMF.__file__, ESMF.__version__)" \
    && /databricks/python3/bin/pip install --ignore-installed \
  six==1.15.0 \
  # downgrade ipython to maintain backwards compatibility with 7.x and 8.x runtimes
  ipython \
  numpy \
  pandas \
  pyarrow \
  matplotlib \
  jinja2 \
  "dask[complete]" \
  cfgrib \
  netCDF4 \
  "xarray[complete]" \
  zarr \
  rioxarray \
  prefect \
  bokeh \
  ipykernel \
  hvplot \
  pangeo-forge-recipes \
  geopandas \
  scipy \
  xclim \
  s3fs \
  gcsfs \
  fsspec \
  && /databricks/python3/bin/pip install --no-dependencies \
  pangeo-xesmf
  
# Specifies where Spark will look for the python process
ENV PYSPARK_PYTHON=/databricks/python3/bin/python3

RUN apt-get update \
  && apt-get install -y fuse \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Make sure the USER env variable is set. The files exposed
# by dbfs-fuse will be owned by this user.
# Within the container, the USER is always root.
ENV USER root

RUN apt-get update \
  && apt-get install -y openssh-server \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Warning: the created user has root permissions inside the container
# Warning: you still need to start the ssh process with `sudo service ssh start`
RUN useradd --create-home --shell /bin/bash --groups sudo ubuntu
